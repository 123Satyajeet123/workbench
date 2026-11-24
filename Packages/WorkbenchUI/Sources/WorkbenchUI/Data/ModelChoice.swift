import AgentCLI
import Foundation
import Observation
import WorkbenchCore

struct ModelChoice: Codable, Hashable, Identifiable {
    var kind: AgentCLIKind
    var model: String

    var id: String { "\(kind.rawValue) \(model)" }

    var title: String {
        switch kind {
        case .claude: "Claude \(model.capitalized)"
        case .codex: "Codex \(model)"
        }
    }

    static let choices = [
        ModelChoice(kind: .claude, model: "opus"), ModelChoice(kind: .claude, model: "sonnet"),
        ModelChoice(kind: .codex, model: "gpt-6.2-sol"),
    ]

    /// The Claude model that searches the web for `ModelSearch`, whatever model the founder picked for reading.
    static let searchModelName = "claude-sonnet-5-5"

    static func with(id: String) -> ModelChoice? { choices.first { $0.id == id } }

    private static let stateKey = StateKey<ModelChoice>.json("model")

    static func saved(in store: Store) throws -> ModelChoice { try stateKey.load(from: store) ?? choices[0] }

    func save(to store: Store) throws { try Self.stateKey.save(self, to: store) }

    nonisolated private static func recordLimits(in store: Store) -> @Sendable (PlanLimits) -> Void {
        { limits in Task { @MainActor in PlanUsage.record(limits, in: store) } }
    }

    /// The runner for this choice, billed as the founder chose: their Claude sign-in, or their own API key. A key goes
    /// only to the Claude CLI; with billing set to a key and none saved, calls stop rather than use the sign-in.
    func model(store: Store, secrets: SecretStore) -> RecordedModel {
        Self.recorded(
            kind: kind, model: model, effort: "medium", timeout: .seconds(300), tools: .none, store: store,
            secrets: secrets)
    }

    /// The Claude model that searches the web for `ModelSearch`, whatever model the founder picked for reading. It is
    /// the model of the dev probe, billed as the founder chose.
    static func searchModel(store: Store, secrets: SecretStore) -> RecordedModel {
        recorded(
            kind: .claude, model: searchModelName, effort: "low", timeout: .seconds(120), tools: .webSearch,
            store: store, secrets: secrets)
    }

    private static func recorded(
        kind: AgentCLIKind, model: String, effort: String, timeout: Duration, tools: AgentTools, store: Store,
        secrets: SecretStore
    ) -> RecordedModel {
        let byKey = kind == .claude && Billing.saved(in: store) == .apiKey
        let runner = AgentRunner(
            kind: kind, model: model, effort: effort, timeout: timeout,
            apiKey: byKey ? secrets.read(Billing.keyName) : nil, requiresAPIKey: byKey, tools: tools,
            workDirectory: store.agentWork,
            onLimits: kind == .claude && !byKey ? Self.recordLimits(in: store) : nil)
        return RecordedModel(runner, store: store)
    }
}

struct ModelMaker {
    private let store: Store
    private let make: (ModelChoice) -> RecordedModel

    init(store: Store, make: ((ModelChoice) -> RecordedModel)?) {
        self.store = store
        self.make = make ?? { $0.model(store: store, secrets: Profile.yours.secrets) }
    }

    func callAsFunction(_ choice: ModelChoice) -> RecordedModel { make(choice) }

    func current() throws -> RecordedModel { make(try ModelChoice.saved(in: store)) }
}

/// Who pays for model calls. Anthropic's terms point programs to the user's own API key; the Claude plan sign-in stays
/// for personal use (code.claude.com/docs/en/legal-and-compliance).
enum Billing: String, CaseIterable, Identifiable {
    case plan, apiKey

    var id: String { rawValue }
    var title: String {
        switch self {
        case .plan: "My Claude plan (sign-in)"
        case .apiKey: "My Anthropic API key (pay per use)"
        }
    }

    static let keyName = "anthropic-api-key"
    private static let stateKey = StateKey<Billing>(
        name: "model.billing", write: \.rawValue, read: { Billing(rawValue: $0) })

    static func saved(in store: Store) -> Billing { ((try? stateKey.load(from: store)) ?? nil) ?? .plan }

    func save(to store: Store) throws { try Self.stateKey.save(self, to: store) }
}

@Observable
final class ModelSettings {
    var choice: ModelChoice {
        didSet {
            do {
                try choice.save(to: store)
                problems.dismiss()
            } catch {
                problems.show("Your model choice was not saved: \(error.localizedDescription)")
            }
        }
    }
    let problems = ProblemSlot()
    var problem: String? { problems.text }
    var billing: Billing {
        didSet { problems.attempt("save the billing choice", clearing: true) { try billing.save(to: store) } }
    }
    private(set) var hasAPIKey: Bool

    @ObservationIgnored let store: Store
    @ObservationIgnored private let secrets: SecretStore

    init(store: Store, secrets: SecretStore) {
        self.store = store
        self.secrets = secrets
        billing = Billing.saved(in: store)
        hasAPIKey = secrets.read(Billing.keyName) != nil
        do {
            choice = try ModelChoice.saved(in: store)
        } catch {
            choice = ModelChoice.choices[0]
            problems.show("Your saved model choice could not be read: \(error.localizedDescription)")
        }
    }

    /// Keeps the key in the Keychain only; the store holds just the billing choice.
    func saveAPIKey(_ key: String) {
        guard let key = key.cleaned else { return }
        problems.attempt("save the key", clearing: true) { try secrets.save(key, as: Billing.keyName) }
        hasAPIKey = secrets.read(Billing.keyName) != nil
    }

    func removeAPIKey() {
        problems.attempt("remove the key", clearing: true) { try secrets.remove(Billing.keyName) }
        hasAPIKey = secrets.read(Billing.keyName) != nil
    }
}

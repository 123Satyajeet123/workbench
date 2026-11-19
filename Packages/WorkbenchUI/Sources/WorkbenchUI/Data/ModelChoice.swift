import AgentCLI
import Foundation
import Observation
import WorkbenchCore

/// Which agent CLI and model reads for Workbench. The founder picks it; the Runs page compares the picks.
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

    static func with(id: String) -> ModelChoice? { choices.first { $0.id == id } }

    private static let stateKey = "model"

    static func saved(in store: Store) throws -> ModelChoice {
        try store.queries.state(forKey: stateKey).map { try JSONDecoder().decode(Self.self, from: Data($0.utf8)) }
            ?? choices[0]
    }

    func save(to store: Store) throws {
        try store.saveState(String(decoding: try JSONEncoder().encode(self), as: UTF8.self), forKey: Self.stateKey)
    }

    /// The runner for this choice, billed as the founder chose: their Claude sign-in, or their own API key. A key goes
    /// only to the Claude CLI; with billing set to a key and none saved, calls stop rather than use the sign-in.
    func model(store: Store, secrets: SecretStore = KeychainSecrets()) -> RecordedModel {
        let byKey = kind == .claude && Billing.saved(in: store) == .apiKey
        let runner = AgentRunner(
            kind: kind, model: model, effort: "medium", timeout: .seconds(300),
            apiKey: byKey ? secrets.read(Billing.keyName) : nil, requiresAPIKey: byKey)
        return RecordedModel(runner, store: store)
    }
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
    private static let stateKey = "model.billing"

    static func saved(in store: Store) -> Billing {
        ((try? store.queries.state(forKey: stateKey)) ?? nil).flatMap(Billing.init(rawValue:)) ?? .plan
    }

    func save(to store: Store) throws { try store.saveState(rawValue, forKey: Self.stateKey) }
}

/// The founder's model pick, shared by every helper. The store holds it; a helper reads it when it starts a read.
@Observable
final class ModelSettings {
    var choice: ModelChoice {
        didSet {
            do {
                try choice.save(to: store)
                problem = nil
            } catch {
                problem = "Your model choice was not saved: \(error.localizedDescription)"
            }
        }
    }
    private(set) var problem: String?
    var billing: Billing {
        didSet { attempt("save the billing choice") { try billing.save(to: store) } }
    }
    private(set) var hasAPIKey: Bool

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let secrets: SecretStore

    init(store: Store, secrets: SecretStore = KeychainSecrets()) {
        self.store = store
        self.secrets = secrets
        billing = Billing.saved(in: store)
        hasAPIKey = secrets.read(Billing.keyName) != nil
        do {
            choice = try ModelChoice.saved(in: store)
        } catch {
            choice = ModelChoice.choices[0]
            problem = "Your saved model choice could not be read: \(error.localizedDescription)"
        }
    }

    /// Keeps the key in the Keychain only; the store holds just the billing choice.
    func saveAPIKey(_ key: String) {
        guard let key = key.cleaned else { return }
        attempt("save the key") { try secrets.save(key, as: Billing.keyName) }
        hasAPIKey = secrets.read(Billing.keyName) != nil
    }

    func removeAPIKey() {
        attempt("remove the key") { try secrets.remove(Billing.keyName) }
        hasAPIKey = secrets.read(Billing.keyName) != nil
    }

    private func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
            problem = nil
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }
}

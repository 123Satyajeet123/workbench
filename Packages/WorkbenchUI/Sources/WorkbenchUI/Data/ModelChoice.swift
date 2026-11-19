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

    private static let stateKey = "model"

    static func saved(in store: Store) throws -> ModelChoice {
        try store.queries.state(forKey: stateKey).map { try JSONDecoder().decode(Self.self, from: Data($0.utf8)) }
            ?? choices[0]
    }

    func save(to store: Store) throws {
        try store.saveState(String(decoding: try JSONEncoder().encode(self), as: UTF8.self), forKey: Self.stateKey)
    }

    func model(store: Store) -> RecordedModel {
        RecordedModel(AgentRunner(kind: kind, model: model, effort: "medium", timeout: .seconds(300)), store: store)
    }
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

    @ObservationIgnored private let store: Store

    init(store: Store) {
        self.store = store
        do {
            choice = try ModelChoice.saved(in: store)
        } catch {
            choice = ModelChoice.choices[0]
            problem = "Your saved model choice could not be read: \(error.localizedDescription)"
        }
    }
}

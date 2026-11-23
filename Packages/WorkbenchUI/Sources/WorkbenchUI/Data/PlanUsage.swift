import Foundation
import Observation
import WorkbenchCore

@Observable
final class PlanUsage {
    private static let key = StateKey<PlanLimits>.json("claude.limits")
    private static let changed = Notification.Name("WorkbenchPlanLimitsChanged")

    private(set) var limits: PlanLimits?
    private(set) var isRefreshing = false
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let probe: () -> RecordedModel
    @ObservationIgnored nonisolated(unsafe) private var listening: (any NSObjectProtocol)?

    init(store: Store, probe: (() -> RecordedModel)? = nil) {
        self.store = store
        self.probe = probe ?? { ModelChoice(kind: .claude, model: "haiku").model(store: store) }
        reload()
        listening = NotificationCenter.default.addObserver(forName: Self.changed, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.reload() }
        }
    }

    deinit { listening.map(NotificationCenter.default.removeObserver) }

    static func record(_ limits: PlanLimits, in store: Store) {
        do {
            try key.save(limits, to: store)
            NotificationCenter.default.post(name: changed, object: nil)
        } catch {
            NSLog("Workbench could not save the Claude plan limits: \(error.localizedDescription)")
        }
    }

    func refresh() async {
        isRefreshing = true
        await problems.attempt("check your Claude plan", clearing: true) {
            _ = try await probe().generate(
                Ping.self, schema: .object([.init("ok", .boolean)]), task: "usage.refresh",
                instructions: "Set ok to true.", input: "ok", holding: [])
        }
        reload()
        isRefreshing = false
    }

    private func reload() {
        problems.attempt("read your Claude plan limits") { limits = try Self.key.load(from: store) }
    }

    nonisolated private struct Ping: Decodable, Sendable { var ok: Bool }
}

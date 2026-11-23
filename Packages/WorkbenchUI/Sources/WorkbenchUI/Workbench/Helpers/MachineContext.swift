import CaptureService
import Foundation
import Observation
import WorkbenchCore

@Observable
final class MachineContext {
    private(set) var machine: Machine
    private(set) var day: WorkDay
    let problems = ProblemSlot()
    let notifications: Notifications

    @ObservationIgnored let source: any MachineSource
    @ObservationIgnored let store: Store
    @ObservationIgnored let makeModel: (ModelChoice) -> RecordedModel
    /// Called after a read or a mark changed this machine's items, so the review queue can follow.
    @ObservationIgnored var itemsChanged: () -> Void = {}
    @ObservationIgnored var reload: () -> Void = {}

    init(
        machine: Machine, source: any MachineSource, store: Store, makeModel: ((ModelChoice) -> RecordedModel)?,
        notifications: Notifications
    ) {
        self.machine = machine
        self.source = source
        self.store = store
        self.makeModel = makeModel ?? { $0.model(store: store) }
        self.notifications = notifications
        day = WorkDay(containing: store.clock())
    }

    var spec: HelperSpec { machine.spec }
    var name: String { machine.name }
    var isPaused: Bool { machine.state == .paused }
    var today: WorkDay { WorkDay(containing: store.clock()) }

    func use(_ machine: Machine) { self.machine = machine }
    func show(_ day: WorkDay) { self.day = day }

    func reloadIfShown(_ other: WorkDay) {
        if day == other { reload() }
    }

    func items(on day: WorkDay) -> [Item] {
        var found: [Item] = []
        problems.attempt("read the items") {
            found = try store.queries.items(of: spec.task, day: day, scope: source.scope)
        }
        return found
    }

    func missing(on day: WorkDay) -> [String] {
        guard let nudge = spec.nudge else { return [] }
        let named = Set(items(on: day).map { $0[nudge.field] })
        return (source.context[nudge.expected] ?? []).filter { !named.contains($0) }
    }

    /// The founder's marked items of the last 60 days: the reader takes examples from them by its own rule.
    func marked() throws -> [Item] {
        try store.queries.items(of: spec.task, since: today.adding(days: -60)).filter { $0.state != .proposed }
    }

    /// The model a version reads with: its own runner, else the founder's choice.
    func runner(for version: HelperModel.Version) throws -> ModelChoice {
        try version.runner.flatMap(ModelChoice.with(id:)) ?? ModelChoice.saved(in: store)
    }

    /// The source must allow the read: for several chats, each one of them.
    func grant() async throws -> CaptureGrant {
        let labels = source.grantLabels
        for label in labels.dropLast() { _ = try await grant(label) }
        return try await grant(labels.last ?? nil)
    }

    private func grant(_ label: String?) async throws -> CaptureGrant {
        try await store.grant(for: spec.source.kind, label: label, at: store.clock())
    }
}

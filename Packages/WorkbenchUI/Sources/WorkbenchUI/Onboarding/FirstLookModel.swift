import Foundation
import Observation
import WorkbenchCore

/// The first look of a new team: the last days of what its machines read, read now through the same path as a normal
/// reading (consent, labels, run records, the verifier), and shown as the main view of the template. Which machines
/// read and what shows follow the template's data and each machine's spec.
@Observable
final class FirstLookModel {
    enum Phase: Equatable {
        case ready
        case reading(day: Int, of: Int)
        case done
    }

    struct Row: Identifiable, Equatable {
        let fact: FactRow
        /// The call on a rated item, with the rules it rests on.
        let triage: Triage?
        var id: Int64 { fact.id }
    }

    private(set) var phase = Phase.ready
    private(set) var cost = FirstLookCost(calls: 0, measured: nil)
    private(set) var rows: [Row] = []
    private(set) var problem: String?
    /// How many days back to read, from one to `FirstLook.defaultDays`: nothing older is kept.
    var days = FirstLook.defaultDays

    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let tasks: Set<String>
    @ObservationIgnored private let today: WorkDay
    @ObservationIgnored private let now: () -> Date

    init(crew: Crew, template: TeamTemplate, today: WorkDay, now: @escaping () -> Date = { .now }) {
        self.crew = crew
        tasks = Set(template.seeds.map(\.spec.task))
        self.today = today
        self.now = now
    }

    /// The machines of the template that read day by day and have a source to read now. A news or search machine
    /// reads on its own schedule.
    var machines: [HelperModel] {
        crew.machines.filter {
            tasks.contains($0.machine.template) && !$0.isOutbound && !($0.source is NewsSource) && $0.isReady
        }
    }

    private var window: [WorkDay] { FirstLook.days(min(max(days, 1), FirstLook.defaultDays), endingOn: today) }

    /// What the reading costs at most: one call for each day of each ready machine that has lines on that day.
    func estimate() async {
        var calls = 0
        for machine in machines {
            for day in window {
                if (try? await machine.source.evidence(on: day).lines.isEmpty) == false { calls += 1 }
            }
        }
        cost = FirstLookCost(
            calls: calls, measured: try? crew.store.queries.averageRunCost(ofTasks: machines.map(\.spec.task)))
    }

    var hasReadySource: Bool { !machines.isEmpty }

    /// Reads each day of the window, oldest first, with every ready machine.
    func run() async {
        guard phase == .ready else { return }
        let window = window
        problem = hasReadySource ? nil : "No source is turned on yet, so there is nothing to read. Turn one on first."
        guard problem == nil else { return }
        for (index, day) in window.enumerated() {
            phase = .reading(day: index + 1, of: window.count)
            for machine in machines { await machine.reading.read(day) }
        }
        problem = machines.compactMap(\.problem).first
        rows = shownRows()
        phase = .done
    }

    /// The main view of the template: its first machine's items of the window, as that machine's spec shows them.
    private func shownRows() -> [Row] {
        guard let main = machines.first else { return [] }
        let spec = main.spec
        let items = main.items(since: window.count)
        return FirstLook.shown(items, by: spec, at: now()).compactMap { item in
            FactRow(item: item, title: item[spec.title]).map { Row(fact: $0, triage: spec.triage(of: item)) }
        }
    }

    /// Marks an item right or wrong, as on the machine's page; the marks of a learn day train the machine.
    func mark(_ row: Row, as mark: Mark) {
        guard let main = machines.first else { return }
        main.mark(row.fact.item, as: mark)
        rows = shownRows()
    }
}

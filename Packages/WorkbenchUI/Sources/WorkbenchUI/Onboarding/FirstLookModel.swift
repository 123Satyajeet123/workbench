import Foundation
import Observation
import WorkbenchCore

/// The first look of a new team: the last days of what its machines read, read now through the same path as a normal
/// reading (consent, labels, run records, the verifier), and shown as each machine's own view. Which machines read and
/// what shows follow the template's data and each machine's spec.
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

    /// One machine's items of the window, as its own spec shows them.
    struct Shown: Identifiable, Equatable {
        let id: Int64
        let name: String
        let rows: [Row]
    }

    private(set) var phase = Phase.ready
    private(set) var cost = FirstLookCost(calls: 0, measured: nil)
    private(set) var shown: [Shown] = []
    private(set) var problem: String?
    /// How many days back to read, from one to `FirstLook.defaultDays`: nothing older is kept.
    var days = FirstLook.defaultDays

    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let tasks: Set<String>
    @ObservationIgnored private let prompts: [TeamStart.Prompt]
    @ObservationIgnored private let today: WorkDay
    @ObservationIgnored private let now: () -> Date

    init(
        crew: Crew, template: TeamTemplate, prompts: [TeamStart.Prompt], today: WorkDay,
        now: @escaping () -> Date = { .now }
    ) {
        self.crew = crew
        tasks = Set(template.seeds.map(\.spec.task))
        self.prompts = prompts
        self.today = today
        self.now = now
    }

    /// The machines of the template that read day by day and have a source to read now. A news or search machine
    /// reads on its own schedule.
    var machines: [HelperModel] {
        seeded.filter { !$0.isOutbound && !($0.source is NewsSource) && $0.isReady }
    }

    /// The machines whose picker waits for the person, such as the chats a chat machine reads, from the prompts that
    /// starting the team returned.
    var choosers: [HelperModel] {
        prompts.compactMap { prompt in
            guard case .picker = prompt.block, let machine = prompt.machine else { return nil }
            return crew.helper(id: machine)
        }
    }

    /// Every row shown, machine by machine.
    var rows: [Row] { shown.flatMap(\.rows) }

    private var seeded: [HelperModel] { crew.machines.filter { tasks.contains($0.machine.template) } }

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
        shown = machines.map(shown)
        phase = .done
    }

    private func shown(_ machine: HelperModel) -> Shown {
        let spec = machine.spec
        let rows = FirstLook.shown(machine.items(since: window.count), by: spec, at: now()).compactMap { item in
            FactRow(item: item, title: item[spec.title]).map { Row(fact: $0, triage: spec.triage(of: item)) }
        }
        return Shown(id: machine.machine.id, name: machine.name, rows: rows)
    }

    /// Marks an item right or wrong, as on its machine's page; the marks of a learn day train the machine.
    func mark(_ row: Row, as mark: Mark) {
        guard let machine = crew.helper(task: row.fact.item.task) else { return }
        machine.mark(row.fact.item, as: mark)
        shown = machines.map(shown)
    }
}

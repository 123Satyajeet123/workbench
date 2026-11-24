import Foundation
import Observation
import WorkbenchCore

/// When a fact added by hand is due.
enum DueChoice: Hashable {
    case none, today, tomorrow, nextWeek
    case day(WorkDay)

    static let quick: [DueChoice] = [.none, .today, .tomorrow, .nextWeek]

    var title: String {
        switch self {
        case .none: "No due day"
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "In a week"
        case .day(let day): day.description
        }
    }

    func day(from today: WorkDay) -> WorkDay? {
        switch self {
        case .none: nil
        case .today: today
        case .tomorrow: today.adding(days: 1)
        case .nextWeek: today.adding(days: 7)
        case .day(let day): day
        }
    }
}

/// The fields of a fact the person adds by hand. Return in the words adds it.
@Observable
final class AddFactModel {
    let kinds: [String]
    let people: [String]
    let today: WorkDay
    var kind: String
    var words = ""
    var person = ""
    var project: String
    var due = DueChoice.none
    private(set) var problem: String?
    private let add: (HandFact) throws -> Void

    init(
        spec: HelperSpec, people: [String] = [], project: String = "",
        today: WorkDay = WorkDay(containing: .now),
        add: @escaping (HandFact) throws -> Void
    ) {
        kinds = spec.factKinds
        kind = spec.factKinds.first ?? ""
        self.people = people
        self.project = project
        self.today = today
        self.add = add
    }

    var canAdd: Bool { words.cleaned != nil && kinds.contains(kind) }

    /// Adds the fact. True when it was added, and the sheet can close.
    func submit() -> Bool {
        guard canAdd else { return false }
        do {
            try add(
                HandFact(
                    kind: kind, text: words, person: person.cleaned ?? "", project: project.cleaned ?? "",
                    due: due.day(from: today)))
            problem = nil
            return true
        } catch {
            problem = "Could not add the fact. Try again."
            return false
        }
    }
}

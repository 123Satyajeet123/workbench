import EditorHarness
import Foundation

@testable import WorkbenchCore

/// The rules code holds about a form, each checked in both directions: the sound one passes, the unsound one is refused.
enum Rules {
    static func run() throws -> [String] {
        let team = Extreme.items(groups: 9, perGroup: 2)
        let few = Extreme.items(groups: 5, perGroup: 2)
        let gate = { (items: [Item], spec: HelperSpec) in PageGate(catalog: PageCatalog(spec: spec, items: items)) }
        func refusal(_ view: FactsView, _ items: [Item], _ spec: HelperSpec = .team) -> PageRefusal? {
            gate(items, spec).refusal(for: .facts(view), on: MachinePage())
        }
        let board = FactsView(title: "Board", groupBy: "person", layout: .board)
        guard refusal(board, team) == .boardTooWide(field: "person", values: 9, cap: 6) else {
            throw DemoFailure("a board of 9 columns was not refused")
        }
        guard refusal(board, few) == nil else { throw DemoFailure("a board of 5 columns was refused") }
        guard refusal(FactsView(title: "Counted", layout: .list, countBy: "kind"), team) == .countsWithoutSections
        else {
            throw DemoFailure("counting with no sections was not refused")
        }
        guard refusal(FactsView(title: "Counted", groupBy: "person", layout: .list, countBy: "kind"), team) == nil
        else {
            throw DemoFailure("counting sections by kind was refused")
        }
        guard refusal(FactsView(title: "Open", layout: .list, show: .open), team, .dealIntake) == .nothingOpens else {
            throw DemoFailure("showing the open facts of a machine with no lifecycle was not refused")
        }
        guard refusal(FactsView(title: "Open", layout: .list, show: .open), team) == nil else {
            throw DemoFailure("showing the open facts of a machine with a lifecycle was refused")
        }
        let columns = FactsView(title: "T", groupBy: "person", layout: .table, columns: ["person", "kind"]).shownColumns
        guard columns == ["kind"] else { throw DemoFailure("a table kept its group field as a column: \(columns)") }
        return [
            "board: 9 columns refused, 5 accepted (cap 6)", "countBy: refused without sections, accepted with them",
            "show open: refused for a machine with no lifecycle, accepted with one",
            "table drops the group field column",
        ]
    }

    /// The first form, from structure alone, for each machine shape: never a board, and the same function for all.
    static func firstForms() throws -> [String] {
        var lines: [String] = []
        for (name, spec, items) in [
            ("team", HelperSpec.team, Extreme.items(groups: 9, perGroup: 3)),
            ("one group", .team, Extreme.items(groups: 1, perGroup: 4)),
            ("no facts", .team, []),
        ] {
            let views = FirstForm.views(of: spec, items: items, lens: FactsLens(spec: spec, now: Date()))
            guard views.allSatisfy({ $0.layout != .board }) else {
                throw DemoFailure("\(name): the first form has a board")
            }
            lines.append(
                "\(name): "
                    + views.map { "\($0.title) [\($0.layout.rawValue)\($0.groupBy.map { " by \($0)" } ?? "")]" }.joined(
                        separator: ", "))
        }
        return lines
    }
}

import EditorHarness
import Foundation
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

/// A set of facts at one extreme: one group, many groups, long names, a long fact, many facts, none.
struct Extreme {
    var name: String
    var items: [Item]

    static func all() -> [Extreme] {
        [
            Extreme(name: "one-group", items: items(groups: 1, perGroup: 8)),
            Extreme(name: "twelve-groups", items: items(groups: 12, perGroup: 3)),
            Extreme(name: "long-names", items: items(groups: 4, perGroup: 3, nameLength: 60)),
            Extreme(name: "long-fact", items: items(groups: 3, perGroup: 3, quoteLength: 400)),
            Extreme(name: "two-hundred-facts", items: items(groups: 9, perGroup: 23)),
            Extreme(name: "empty", items: []),
        ]
    }

    /// Facts of the team spec made in memory: a name without spaces when `nameLength` asks for one, a quote cut to
    /// `quoteLength` characters.
    static func items(groups: Int, perGroup: Int, nameLength: Int? = nil, quoteLength: Int = 70) -> [Item] {
        let kinds = ["plan", "done", "blocker", "commitment", "decision", "question", "status"]
        let sentence = "The invented work moves on and the next step waits for a reply from the partner. "
        var made: [Item] = []
        for group in 0..<groups {
            let name =
                nameLength.map { String(String(repeating: "Longname\(group)", count: 9).prefix($0)) }
                ?? "Person \(group) Example"
            for index in 0..<perGroup {
                let quote = String(String(repeating: sentence, count: 8).prefix(quoteLength))
                made.append(
                    Item(
                        id: Int64(made.count + 1), task: "team.ledger", day: WorkDay(containing: Date()),
                        scope: "stress",
                        source: .whatsapp, citeFirst: 1, citeLast: 1, start: Date(), end: Date(),
                        fields: [
                            "person": name, "project": "Project \(index % 3)",
                            "kind": kinds[(group + index) % kinds.count],
                            "asks": index % 4 == 0 ? "founder" : "team",
                        ], quote: quote, run: nil,
                        due: index % 5 == 0 ? Due.stated(on: WorkDay(containing: Date()).adding(days: -2)) : nil))
            }
        }
        return made
    }
}

/// The layouts at the person's column, each as a view over the field `person`.
enum StressLayout: String, CaseIterable {
    case list, board, table, counts
    case foldedList = "folded-list"
    case foldedTable = "folded-table"

    var view: FactsView {
        switch self {
        case .list: FactsView(title: "List", groupBy: "person", layout: .list)
        case .board: FactsView(title: "Board", groupBy: "person", layout: .board)
        case .table: FactsView(title: "Table", groupBy: "person", layout: .table, columns: ["person", "kind", "quote"])
        case .counts: FactsView(title: "Counts", groupBy: "person", layout: .counts)
        case .foldedList:
            FactsView(title: "Folded list", groupBy: "person", layout: .list, countBy: "kind", order: .urgent)
        case .foldedTable:
            FactsView(title: "Folded table", groupBy: "person", layout: .table, countBy: "kind", order: .urgent)
        }
    }
}

/// What the page measured about itself, in points, with every fold open.
struct PageMeasure: Codable {
    var overflow: Int
    var narrowest: Double
    var facts: Int
    var height: Int
    var overlaps: Int
    var asList: Bool
    var offenders: String
}

enum Stress {
    static let minimumWords = 160.0
    static let width: CGFloat = 700

    static func run(into folder: URL) async throws -> [String] {
        var report: [String] = []
        for layout in StressLayout.allCases {
            let desk = try await Desk(texts: [], spec: .team, name: "stress")
            defer { desk.close() }
            try desk.clearMachineBlocks()
            try desk.addMachineBlocks([(.facts(layout.view), after: nil)])
            for extreme in Extreme.all() {
                try groupFieldAbsent(
                    layout.view, extreme.items, spec: desk.machine!.spec, where: "\(layout.rawValue) \(extreme.name)")
                let session = try await Session(
                    desk: desk, width: width, facts: extreme.items, ready: Session.blocksReady)
                try await Task.sleep(for: .milliseconds(200))
                let measure = try await measure(session.editor)
                let label = "\(layout.rawValue) / \(extreme.name)"
                guard measure.overlaps == 0 else {
                    throw DemoFailure(
                        "\(label): \(measure.overlaps) table cells overlap or spill (\(measure.offenders))")
                }
                guard measure.overflow == 0 else {
                    throw DemoFailure("\(label): \(measure.overflow) elements stick out of the page column")
                }
                guard measure.narrowest >= minimumWords else {
                    throw DemoFailure("\(label): a view is \(measure.narrowest) pt wide, under \(minimumWords)")
                }
                let expected = layout == .counts ? 0 : extreme.items.count
                guard measure.facts == expected else {
                    throw DemoFailure("\(label): \(measure.facts) fact rows drawn, \(expected) expected")
                }
                try await session.editor.fullPagePNG(
                    to: folder.appending(path: "stress/\(layout.rawValue)-\(extreme.name)-700-light.png"))
                report.append("\(label): ok, narrowest \(Int(measure.narrowest)) pt, page \(measure.height) pt")
            }
        }
        report += try await foldedTableFit(in: folder)
        report.append(try await control(in: folder))
        return report
    }

    /// The rule that decides between the table and the list: seven count columns fit in a window of 700 pt or more, and
    /// do not in a window of 500 pt, where the same sections show as folded rows. No cell overlaps another either way.
    private static func foldedTableFit(in folder: URL) async throws -> [String] {
        let desk = try await Desk(texts: [], spec: .team, name: "fit")
        defer { desk.close() }
        try desk.clearMachineBlocks()
        try desk.addMachineBlocks([(.facts(StressLayout.foldedTable.view), after: nil)])
        var lines: [String] = []
        for (window, wantsList) in [(1000.0, false), (700.0, false), (500.0, true)] {
            let session = try await Session(
                desk: desk, width: window, facts: Extreme.items(groups: 9, perGroup: 7), ready: Session.blocksReady)
            try await Task.sleep(for: .milliseconds(300))
            let measure = try await measure(session.editor)
            guard measure.overlaps == 0 else {
                throw DemoFailure("fit \(Int(window)): \(measure.overlaps) cells overlap")
            }
            guard measure.asList == wantsList else {
                throw DemoFailure(
                    "fit \(Int(window)): form is \(measure.asList ? "list" : "table"), expected \(wantsList ? "list" : "table")"
                )
            }
            try await session.editor.fullPagePNG(
                to: folder.appending(path: "stress/fit-folded-table-\(Int(window)).png"))
            lines.append("folded table in a \(Int(window)) pt window: \(measure.asList ? "list" : "table"), no overlap")
        }
        return lines
    }

    /// The check must fail on a defect: the old board, whose columns shrank with their number, drawn at 12 groups.
    private static func control(in folder: URL) async throws -> String {
        let desk = try await Desk(texts: [], spec: .team, name: "control")
        defer { desk.close() }
        try desk.clearMachineBlocks()
        try desk.addMachineBlocks([(.facts(StressLayout.board.view), after: nil)])
        let session = try await Session(
            desk: desk, width: width, facts: Extreme.items(groups: 12, perGroup: 3), ready: Session.blocksReady)
        try await session.editor.run(
            "document.querySelectorAll('.facts-section').forEach((node) => { node.style.flex = '1'; node.style.minWidth = '0'; node.style.width = 'auto'; });"
        )
        let measure = try await measure(session.editor)
        guard measure.narrowest < minimumWords else {
            throw DemoFailure("control: the old board was not caught (\(measure.narrowest) pt)")
        }
        return
            "control: the old shrinking board measures \(Int(measure.narrowest)) pt and is caught (minimum \(Int(minimumWords)) pt)"
    }

    /// Opens every fold, then counts what sticks out of the page column (outside a box that scrolls on its own), the
    /// narrowest view that is drawn, and the fact rows in the page.
    private static func measure(_ editor: OffscreenEditor) async throws -> PageMeasure {
        let json = try await editor.json(
            """
            document.querySelectorAll('details').forEach((node) => { node.open = true; });
            document.querySelectorAll('.group-toggle').forEach((node) => node.click());
            await new Promise((done) => setTimeout(done, 150));
            const page = document.getElementById('page').getBoundingClientRect();
            const outside = [...document.querySelectorAll('#page .machine *')].filter((node) => !node.closest('.table-wrap, .facts-board') && node.getBoundingClientRect().width > 0 && node.getBoundingClientRect().right > page.right + 1).length;
            const drawn = (node) => node.getBoundingClientRect().width > 0;
            let overlaps = 0;
            for (const row of [...document.querySelectorAll('.group-table tr')].filter(drawn)) {
              const boxes = [...row.children].map((cell) => cell.getBoundingClientRect()).filter((box) => box.width > 0).sort((a, b) => a.left - b.left);
              for (let index = 0; index + 1 < boxes.length; index++) if (boxes[index].right > boxes[index + 1].left + 1) overlaps++;
            }
            const spillers = [...document.querySelectorAll('.group-table th, .group-table td')].filter((cell) => drawn(cell) && cell.scrollWidth > cell.clientWidth + 1).map((cell) => `${cell.tagName}.${cell.className}:${cell.textContent.slice(0, 20)}:${cell.scrollWidth}>${cell.clientWidth}`);
            const spill2 = [...document.querySelectorAll('.group-table th, .group-table td')].filter((cell) => drawn(cell) && cell.scrollWidth > cell.clientWidth + 1).length;
            const spill = document.documentElement.scrollWidth > window.innerWidth ? 1 : 0;
            const widths = [...document.querySelectorAll('.fact-words, .group-row, .facts-section, .machine-table')].map((node) => node.getBoundingClientRect().width).filter((width) => width > 0);
            return { overflow: outside + spill, narrowest: widths.length ? Math.min(...widths) : 9999, facts: [...document.querySelectorAll('.machine .fact')].filter((node) => node.getBoundingClientRect().width > 0).length, height: Math.round(document.documentElement.scrollHeight), overlaps: overlaps + spill2, asList: Boolean(document.querySelector('.group-fit.as-list')), offenders: spillers.join(' | ') };
            """)
        return try JSONDecoder().decode(PageMeasure.self, from: Data(json.utf8))
    }

    /// No row repeats the field its section is made of: not as the person's name, not as a tag, not as a column.
    private static func groupFieldAbsent(_ view: FactsView, _ items: [Item], spec: HelperSpec, where label: String)
        throws
    {
        let builder = MachineViewBuilder(
            facts: items, titleOf: { $0[spec.title] }, lens: FactsLens(spec: spec, now: Date()),
            pickerNote: { _ in nil })
        guard case .facts(let drawn) = builder.view(of: .facts(view), erased: false) else {
            throw DemoFailure("\(label): no facts view")
        }
        guard !drawn.columns.contains(view.groupBy ?? "") else {
            throw DemoFailure("\(label): the group field is a column")
        }
        for section in drawn.sections {
            for row in section.rows
            where row.subject == section.name || row.tags.contains(where: { $0.text == section.name }) {
                throw DemoFailure("\(label): a row repeats its section's name \"\(section.name)\"")
            }
        }
    }
}

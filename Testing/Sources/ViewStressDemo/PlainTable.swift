import EditorHarness
import Foundation
import Kernel

@testable import WorkbenchCore

/// The plain facts table, by one rule: every column has a real minimum width, cells wrap inside their column, header
/// and body cells share the edges of their column, and a table whose columns do not fit the block shows its rows as
/// cards with the fields stacked. Measured by bounding boxes, with two, three and six columns, a cell of 400
/// characters and a single word of 60 characters.
enum PlainTable {
    struct Case {
        var name: String
        var columns: [String]
        var text: (Int) -> String
        /// The form the rule must give, or nil when only the boxes are checked.
        var expectsList: Bool?
    }

    struct Measure: Codable {
        var asList: Bool
        var rows: Int
        var overlaps: Int
        var outside: Int
        var misaligned: Int
        var offenders: String
    }

    static let sentence = "The invented work moves on and the next step waits for a reply. "
    static let all = [
        Case(name: "2 columns", columns: ["person", "text"], text: { _ in "Short invented fact" }, expectsList: false),
        Case(
            name: "3 columns", columns: ["person", "kind", "text"], text: { _ in "Short invented fact" },
            expectsList: false),
        Case(
            name: "6 columns", columns: ["person", "project", "kind", "text", "stance", "asks"],
            text: { _ in "Short invented fact" }, expectsList: true),
        Case(
            name: "2 columns, a 400-character cell", columns: ["person", "text"],
            text: { String(String(repeating: sentence, count: 8).prefix($0 == 1 ? 400 : 20)) }, expectsList: false),
        Case(
            name: "3 columns, a 60-character word", columns: ["person", "kind", "text"],
            text: { String(String(repeating: "Longword", count: 9).prefix($0 == 1 ? 60 : 8)) }, expectsList: nil),
    ]

    static func items(_ test: Case) -> [Item] {
        (0..<6).map { index in
            Item(
                id: Int64(index + 1), task: "team.ledger", day: WorkDay(containing: Date()), scope: "plain",
                source: .whatsapp, citeFirst: 1, citeLast: 1, start: Date(), end: Date(),
                fields: [
                    "person": "Person \(index) Example", "project": "Project \(index % 3)", "kind": "plan",
                    "text": test.text(index), "stance": "said", "asks": "team",
                ], quote: "Invented quote \(index)", run: nil)
        }
    }

    static func run(into folder: URL) async throws -> [String] {
        var lines: [String] = []
        for width in [700.0, 1000.0] {
            for test in all {
                let desk = try await Desk(texts: [], spec: .team, name: "plain")
                defer { desk.close() }
                try desk.clearMachineBlocks()
                let view = FactsView(title: "Plain", layout: .table, columns: test.columns)
                try desk.addMachineBlocks([(.facts(view), after: nil)])
                let session = try await Session(
                    desk: desk, width: width, facts: items(test), ready: Session.blocksReady)
                try await Task.sleep(for: .milliseconds(300))
                let measure = try await measure(session.editor)
                let label = "\(test.name) at \(Int(width)) pt"
                guard measure.rows == 6 else { throw DemoFailure("\(label): \(measure.rows) rows drawn, 6 expected") }
                guard measure.overlaps == 0, measure.outside == 0, measure.misaligned == 0 else {
                    throw DemoFailure(
                        "\(label): \(measure.overlaps) overlaps, \(measure.outside) outside the block, \(measure.misaligned) misaligned (\(measure.offenders))"
                    )
                }
                if let wanted = test.expectsList, width == 700, measure.asList != wanted {
                    throw DemoFailure(
                        "\(label): form is \(measure.asList ? "list" : "table"), expected \(wanted ? "list" : "table") (\(measure.offenders))"
                    )
                }
                try await session.editor.fullPagePNG(
                    to: folder.appending(
                        path: "plain-table/\(test.name.filter { $0.isLetter || $0.isNumber })-\(Int(width)).png"))
                lines.append("\(label): \(measure.asList ? "list of cards" : "table"), no overlap, edges shared")
            }
        }
        lines.append(try await control(in: folder))
        return lines
    }

    /// The check must fail on a defect: a row laid out as flex, as the table rows were before the rule.
    private static func control(in folder: URL) async throws -> String {
        let desk = try await Desk(texts: [], spec: .team, name: "plain-control")
        defer { desk.close() }
        try desk.clearMachineBlocks()
        try desk.addMachineBlocks([
            (.facts(FactsView(title: "Plain", layout: .table, columns: ["person", "text"])), after: nil)
        ])
        let session = try await Session(
            desk: desk, width: 700, facts: items(all[3]), ready: Session.blocksReady)
        try await session.editor.run(
            "document.querySelectorAll('.fact-table tbody tr').forEach((row) => { row.style.display = 'flex'; });")
        let measure = try await measure(session.editor)
        guard measure.misaligned > 0 else { throw DemoFailure("control: the flex rows were not caught") }
        return "control: rows laid out as flex give \(measure.misaligned) misaligned cells and are caught"
    }

    private static func measure(_ editor: OffscreenEditor) async throws -> Measure {
        let json = try await editor.json(
            """
            await new Promise((done) => setTimeout(done, 150));
            const drawn = (node) => node.getBoundingClientRect().width > 0;
            const fit = document.querySelector('.fact-fit');
            const block = fit.getBoundingClientRect();
            const asList = fit.classList.contains('as-list');
            let overlaps = 0, outside = 0, misaligned = 0;
            const offenders = [];
            const within = (box) => box.left >= block.left - 1 && box.right <= block.right + 1;
            if (asList) {
              for (const card of [...fit.querySelectorAll('.fact-card')]) {
                if (!within(card.getBoundingClientRect())) outside++;
                const fields = [...card.querySelectorAll('.fact-card-field')].map((node) => node.getBoundingClientRect());
                for (let i = 0; i + 1 < fields.length; i++) if (fields[i].bottom > fields[i + 1].top + 1) overlaps++;
                for (const word of card.querySelectorAll('.fact-card-words')) if (word.scrollWidth > word.clientWidth + 1) outside++;
              }
            } else {
              const rows = [...fit.querySelectorAll('table tr')].filter(drawn);
              const head = [...rows[0].children].map((cell) => cell.getBoundingClientRect());
              for (const row of rows) {
                const boxes = [...row.children].map((cell) => cell.getBoundingClientRect());
                boxes.forEach((box, i) => {
                  if (!within(box)) { outside++; offenders.push('outside ' + i); }
                  if (i + 1 < boxes.length && box.right > boxes[i + 1].left + 1) { overlaps++; offenders.push('overlap ' + i); }
                  if (Math.abs(box.left - head[i].left) > 1 || Math.abs(box.right - head[i].right) > 1) { misaligned++; offenders.push('edge ' + i); }
                });
                for (const cell of row.children) if (cell.scrollWidth > cell.clientWidth + 1) outside++;
              }
            }
            const rowCount = asList ? fit.querySelectorAll('.fact-card').length : document.querySelectorAll('.fact-table tbody tr').length;
            const wrapBox = fit.querySelector('.table-wrap');
            return { asList, rows: rowCount, overlaps, outside, misaligned, offenders: offenders.join(',') + ' wrap ' + (wrapBox ? wrapBox.scrollWidth + '/' + wrapBox.clientWidth : '') + ' th ' + [...fit.querySelectorAll('th')].map((n) => Math.round(n.getBoundingClientRect().width)).join(',') };
            """)
        return try JSONDecoder().decode(Measure.self, from: Data(json.utf8))
    }
}

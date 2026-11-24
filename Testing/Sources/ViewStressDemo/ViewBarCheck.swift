import EditorHarness
import Foundation
import GRDB
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

/// The person's view bar, off screen, through the editor's own controls: the choices are the ones the gate allows, a
/// choice is stored as the person's own edit, and a choice the gate refuses changes nothing.
enum ViewBarCheck {
    static func run() async throws -> [String] {
        let desk = try await Desk(texts: [], spec: .team, name: "bar")
        defer { desk.close() }
        let items = try seed(
            InventedTeam.facts(), in: desk.store, of: desk.machine!, owner: desk.owner, scope: "bar")
        try desk.clearMachineBlocks()
        try desk.addMachineBlocks([
            (
                .facts(
                    FactsView(title: "By person", groupBy: "person", layout: .list, countBy: "kind", order: .urgent)),
                after: nil
            )
        ])
        let session = try await Session(desk: desk, width: 1000, facts: items, ready: Session.blocksReady)
        var lines: [String] = []

        let first = try await choices(session)
        try expect(
            first.forms == ["foldedList", "list", "table", "counts"], "layouts offered for 9 people: \(first.forms)")
        try expect(!first.forms.contains("board"), "a board of 9 people is offered")
        try expect(first.groups == ["person", "project", "stance", "asks"], "groups offered: \(first.groups)")
        lines.append(
            "by person (9 values): layouts \(first.forms), groups \(first.groups); no board, no group by the counted field"
        )

        try await choose(session, "Group by", "project")
        let byProject = try await choices(session)
        try expect(byProject.forms.contains("board"), "a board of 6 projects is not offered: \(byProject.forms)")
        try expect(try await title(session) == "By project", "the title did not follow the group field")
        try expect(try await sectionNames(session).contains("Harbor release"), "the sections are not projects")
        lines.append("group by project: layouts \(byProject.forms) (board now offered, 6 values); title \"By project\"")

        try await choose(session, "Layout", "board")
        try expect(
            try await session.editor.json("return document.querySelectorAll('.facts-board').length") == "1",
            "the board did not draw")
        let states = try rowStates(desk)
        try expect(states == ["replaced", "replaced", "live"], "rows after two changes: \(states)")
        try expect(try liveMadeByPerson(desk) == 1, "the live block is not the person's own (no run, no proposal)")
        lines.append("layout board: rows \(states); the live row has no run and no proposal")

        let before = try rowStates(desk)
        let host = session.editor.host
        host.onMessage?(.ops(seq: 99, ops: [.view(block: try liveID(desk), form: "foldedList", groupBy: "kind")]))
        try await session.settle()
        try expect(try rowStates(desk) == before, "a refused choice changed the store")
        lines.append(
            "a refused choice sent straight to Swift (fold by the field it counts): store unchanged, rows \(before)")
        return lines
    }

    private struct Choices {
        var forms: [String]
        var groups: [String]
    }

    private static func choices(_ session: Session) async throws -> Choices {
        let text = try await session.editor.json(
            """
            const values = (label) => [...document.querySelectorAll(`.view-select[aria-label="${label}"] option`)].map((option) => option.value);
            return { forms: values('Layout'), groups: values('Group by') };
            """)
        struct Decoded: Decodable {
            var forms: [String]
            var groups: [String]
        }
        let decoded = try JSONDecoder().decode(Decoded.self, from: Data(text.utf8))
        return Choices(forms: decoded.forms, groups: decoded.groups)
    }

    private static func choose(_ session: Session, _ label: String, _ value: String) async throws {
        try await session.editor.run(
            """
            const select = document.querySelector('.view-select[aria-label="\(label)"]');
            select.value = '\(value)';
            select.dispatchEvent(new Event('change', { bubbles: true }));
            """)
        try await session.settle()
        try await Task.sleep(for: .milliseconds(400))
    }

    private static func title(_ session: Session) async throws -> String {
        let text = try await session.editor.json("return document.querySelector('.machine-title').textContent")
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private static func sectionNames(_ session: Session) async throws -> [String] {
        let text = try await session.editor.json(
            "return [...document.querySelectorAll('.facts-name, .group-name')].map((node) => node.textContent)")
        return try JSONDecoder().decode([String].self, from: Data(text.utf8))
    }

    private static func rowStates(_ desk: Desk) throws -> [String] {
        try desk.store.writer.read { db in
            try String.fetchAll(
                db,
                sql:
                    "SELECT state FROM machine_block WHERE object_id = ? AND state <> 'removed' ORDER BY made_at, rowid",
                arguments: [desk.page])
        }
    }

    private static func liveMadeByPerson(_ desk: Desk) throws -> Int {
        try desk.store.writer.read { db in
            try Int.fetchOne(
                db,
                sql:
                    "SELECT COUNT(*) FROM machine_block WHERE object_id = ? AND state = 'live' AND made_by_run IS NULL AND proposal_id IS NULL",
                arguments: [desk.page])!
        }
    }

    private static func liveID(_ desk: Desk) throws -> String {
        try desk.store.writer.read { db in
            try String.fetchOne(
                db, sql: "SELECT id FROM machine_block WHERE object_id = ? AND state = 'live'", arguments: [desk.page])!
        }
    }

    private static func expect(_ ok: Bool, _ what: String) throws { if !ok { throw DemoFailure(what) } }
}

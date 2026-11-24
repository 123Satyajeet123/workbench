import EditorHarness
import Foundation
import Kernel

@testable import WorkbenchCore
@testable import WorkbenchUI

/// One form a machine's page can take: the facts views it holds, and whether its folded rows start open.
struct Candidate {
    var name: String
    var views: [FactsView]
    var unfoldFirst = false
}

/// One invented data set and the forms rendered for it.
struct ExpressionSet {
    var name: String
    var spec: HelperSpec
    var facts: [InventedFact]
    var candidates: @MainActor (_ items: [Item], _ lens: FactsLens) -> [Candidate]
    var summaries: @MainActor (_ items: [Item], _ run: RunID) -> [String: Summary] = { _, _ in [:] }
}

/// What one picture measured: how much of the first screen is facts, groups and what needs the person.
struct FirstScreen: Codable {
    var facts: Int
    var groups: Int
    var needs: Int
    var height: Int
}

enum Expression {
    static let widths: [CGFloat] = [700, 1000]
    static let firstScreenHeight = 800

    static func render(_ set: ExpressionSet, into folder: URL) async throws -> [String] {
        var chatSpec = set.spec
        chatSpec.source = .whatsAppChat
        let seedDesk = try await Desk(texts: [], spec: chatSpec, name: set.name)
        defer { seedDesk.close() }
        let items = try seed(
            set.facts, in: seedDesk.store, of: seedDesk.machine!, owner: seedDesk.owner, scope: set.name)
        let lens = FactsLens(spec: set.spec, now: Date())
        let summaries = set.summaries(items, items[0].run!)
        var report: [String] = []
        for candidate in set.candidates(items, lens) {
            let desk = try await Desk(texts: [], spec: set.spec, name: set.name)
            defer { desk.close() }
            try desk.clearMachineBlocks()
            try desk.addMachineBlocks(candidate.views.map { (MachineBlock.facts($0), after: nil) })
            for width in widths {
                for dark in [false, true] {
                    let session = try await Session(
                        desk: desk, dark: dark, width: width, facts: items, summaries: summaries,
                        ready: Session.blocksReady)
                    try await Task.sleep(for: .milliseconds(300))
                    if candidate.unfoldFirst { try await unfold(session.editor) }
                    let name = "\(set.name)-\(candidate.name)-\(Int(width))-\(dark ? "dark" : "light")"
                    let screen = try await measure(session.editor)
                    try await session.editor.fullPagePNG(to: folder.appending(path: "\(name).png"))
                    if !dark {
                        report.append(
                            "\(name): \(screen.facts) facts, \(screen.groups) groups, \(screen.needs) needs-pills in the first \(firstScreenHeight) pt; page \(screen.height) pt"
                        )
                    }
                }
            }
        }
        return report
    }

    private static func unfold(_ editor: OffscreenEditor) async throws {
        try await editor.run(
            """
            document.querySelectorAll('details.group').forEach((node, index) => { if (index === 0) node.open = true; });
            document.querySelectorAll('.group-toggle').forEach((node, index) => { if (index === 0) node.click(); });
            """)
        try await Task.sleep(for: .milliseconds(150))
    }

    static func measure(_ editor: OffscreenEditor) async throws -> FirstScreen {
        let json = try await editor.json(
            """
            const shown = (node) => { const box = node.getBoundingClientRect(); return box.width > 0 && box.height > 0 && box.bottom <= \(firstScreenHeight) && box.right <= window.innerWidth; };
            const count = (selector) => [...document.querySelectorAll(selector)].filter(shown).length;
            return { facts: count('.fact'), groups: count('.group-row, .group-trow'), needs: count('.needs-pill'), height: Math.round(document.documentElement.scrollHeight) };
            """)
        return try JSONDecoder().decode(FirstScreen.self, from: Data(json.utf8))
    }
}

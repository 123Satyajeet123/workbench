import EditorHarness
import Foundation
import Kernel
import PageSnapshot
import SwiftUI

@testable import WorkbenchCore
@testable import WorkbenchUI

/// The first page of a blank machine and what the home shows, drawn off screen into PNG files.
@MainActor
enum Pages {
    /// The facts blocks the page holds, in order: what the first form made from the spec alone.
    static func firstForm(of machine: Machine, in store: Store, owner: PersonID) throws -> [FactsView] {
        guard let page = machine.page else { throw DemoFailure("the machine has no page") }
        let stored = try store.queries.page(of: page, for: PageViewer(owner: owner)).page
        return stored.order.compactMap { place in
            if case .machine(let id) = place, case .facts(let view)? = stored.blocks[id] { view } else { nil }
        }
    }

    static func checkFirstForms(_ machines: [HelperModel], in scratch: Scratch) throws {
        heading("5. The first page, from the spec alone")
        let forms = try machines.map { try firstForm(of: $0.machine, in: scratch.store, owner: scratch.owner) }
        for (helper, form) in zip(machines, forms) {
            print("  \(helper.spec.source.name): \(form.map { "\($0.title) (\($0.layout), columns \($0.columns))" })")
        }
        check(
            "each blank machine starts with one table of its facts",
            forms.allSatisfy { $0.count == 1 && $0[0].layout == .table })
        check(
            "the table shows the one field and the quote",
            forms.allSatisfy { $0.first?.columns == ["text", PageCatalog.quoteColumn] })
        check("no machine blank or not holds a first page with no block", forms.allSatisfy { !$0.isEmpty })
    }

    static func page(of helper: HelperModel, in scratch: Scratch, to folder: URL) async throws -> [URL] {
        guard let model = helper.pageModel else { throw DemoFailure("no page model") }
        helper.reload()
        model.reload()
        let models = ModelSettings(store: scratch.store, secrets: MemorySecrets())
        var files: [URL] = []
        for width in [700.0, 1000.0] {
            for dark in [false, true] {
                files.append(
                    try await snapshot(
                        pageOf: model, crew: scratch.crew, models: models,
                        named: "blank-page-\(Int(width))", dark: dark, size: CGSize(width: width, height: 1500),
                        in: folder))
            }
        }
        return files
    }

    /// The home as the app draws it: its body for the given store state.
    static func home(_ named: String, in scratch: Scratch, to folder: URL) async throws -> [URL] {
        var files: [URL] = []
        for dark in [false, true] {
            let today = scratch.today()
            let view = Page(intro: .mochi, title: "Today", subtitle: "Home") { TodayBody(model: today) }
                .environment(today).environment(scratch.crew).environment(Navigation())
            files.append(
                try await snapshot(
                    view, named: named, dark: dark, size: CGSize(width: 700, height: 700), in: folder))
        }
        return files
    }

    /// The add sheet as it opens: the blank machine first, nothing chosen.
    static func addSheet(in scratch: Scratch, to folder: URL) async throws -> [URL] {
        var files: [URL] = []
        for dark in [false, true] {
            let view = MachineSheet(edit: .new(in: nil)) { _ in }.environment(scratch.crew)
            files.append(
                try await snapshot(
                    view, named: "add-sheet", dark: dark, size: CGSize(width: 520, height: 640), in: folder))
        }
        return files
    }
}

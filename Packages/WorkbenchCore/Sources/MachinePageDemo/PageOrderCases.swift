import Foundation

@testable import WorkbenchCore

/// Where a paragraph lands when the editor saves the order the person sees. Each case runs on a new store with one
/// live machine block, "Mark", after the first paragraph.
enum PageOrderCases {
    static func run(in directory: URL) async throws {
        try await typedAbove(try await world(directory, "above"))
        try await typedBelow(try await world(directory, "below"))
        try await acceptBetweenLoadAndSave(try await world(directory, "accept"))
        try await staleSaveNamesRemovedBlock(try await world(directory, "stale"))
        try await plainNote(try await world(directory, "plain"))
    }

    private static func world(_ directory: URL, _ name: String) async throws -> World {
        try await World.make(in: directory.appending(path: "order-\(name)"))
    }

    private static func typedAbove(_ world: World) async throws {
        let mark = try world.putMarkAfterFirstParagraph()
        let typed = BlockID()
        try await world.saveTyped(
            typed, after: world.paragraphs[0], page: world.page(typed: typed, mark: mark, above: true))
        try world.expectOrder("a. typed above the block", "p1 new h(Mark) p2 p3")
    }

    private static func typedBelow(_ world: World) async throws {
        let mark = try world.putMarkAfterFirstParagraph()
        let typed = BlockID()
        try await world.saveTyped(
            typed, after: world.paragraphs[0], page: world.page(typed: typed, mark: mark, above: false))
        try world.expectOrder("b. typed below the block", "p1 h(Mark) new p2 p3")
    }

    private static func acceptBetweenLoadAndSave(_ world: World) async throws {
        let typed = BlockID()
        _ = try world.putMarkAfterFirstParagraph()
        try await world.saveTyped(typed, after: world.paragraphs[0], page: world.page(typed: typed, mark: nil))
        try world.expectOrder("c. accept between load and save", "p1 h(Mark) new p2 p3")
    }

    private static func staleSaveNamesRemovedBlock(_ world: World) async throws {
        let mark = try world.putMarkAfterFirstParagraph()
        try world.store.removeBlock(mark, surface: .machinePage)
        let typed = BlockID()
        try await world.saveTyped(
            typed, after: world.paragraphs[0], page: world.page(typed: typed, mark: mark, above: false))
        try world.expectOrder("d. stale save names a removed block", "p1 new p2 p3")
    }

    private static func plainNote(_ world: World) async throws {
        let typed = BlockID()
        try await world.saveTyped(typed, after: world.paragraphs[0], page: nil)
        try world.expectOrder("e. plain note, no pageOrder", "p1 new p2 p3")
    }
}

extension World {
    /// A live machine block after the first paragraph, made the way an accept makes it.
    fileprivate func putMarkAfterFirstParagraph() throws -> MachineBlockID {
        let proposal = try propose([.insert(.heading("Mark"), after: .note(paragraphs[0]))], note: "One heading.")
        try store.accept(proposal: proposal, surface: .machinePage)
        return blockIDs(.heading, in: try contents())[0]
    }

    /// Saves one new paragraph typed after `paragraph`, with the order the person sees.
    fileprivate func saveTyped(_ typed: BlockID, after paragraph: BlockID, page: [PageBlockRef]?) async throws {
        var order = paragraphs
        order.insert(typed, at: order.firstIndex(of: paragraph)! + 1)
        try await saveParagraphs(
            [NoteBlock(id: typed, text: "A new paragraph.")], endings: [], order: order, pageOrder: page)
    }

    /// The page the person sees after typing `typed` beside the first paragraph: with `mark` above or below it, or
    /// without a machine block when the editor does not know one.
    fileprivate func page(typed: BlockID, mark: MachineBlockID?, above: Bool = false) -> [PageBlockRef] {
        let first = paragraphs[0]
        let beside: [PageBlockRef] =
            switch (mark, above) {
            case (let mark?, true): [.note(typed), .machine(mark)]
            case (let mark?, false): [.machine(mark), .note(typed)]
            case (nil, _): [.note(typed)]
            }
        return [.note(first)] + beside + paragraphs.dropFirst().map(PageBlockRef.note)
    }

    fileprivate func expectOrder(_ what: String, _ wanted: String) throws {
        let shown = describe(try contents())
        print("\(what): \(shown)")
        try expect(shown, wanted, what)
    }
}

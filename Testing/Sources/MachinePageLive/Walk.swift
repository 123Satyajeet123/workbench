import AppKit
import Foundation
import PageSnapshot

@testable import WorkbenchCore
@testable import WorkbenchUI

struct Expectation: Error, CustomStringConvertible {
    let description: String

    init(_ what: String, expected: String, found: String) {
        description = "FAILED: \(what). Expected: \(expected). Found: \(found)."
    }
}

func expect(_ isMet: Bool, _ what: String, expected: String, found: @autoclosure () -> String) throws {
    if !isMet { throw Expectation(what, expected: expected, found: found()) }
}

/// The script of steps a to g on one private copy of the demo store. It prints each page and draws it offscreen.
final class Walk {
    private static let paragraph = "Budget talk with Asha."
    private static let sentences = "Write two sentences on what the team is working on."
    private static let plainSentences = "Write two sentences on what the team is working on."
    private let shots: URL
    private let session: LiveSession
    private var asks = 0

    init(session: LiveSession, shots: URL) {
        self.session = session
        self.shots = shots
    }

    private var page: MachinePageModel { session.page }

    /// Steps a to f. Answers the page as it ends, flushed to the store, and stops the session's tickers. A run that
    /// `resumesAtSentences` skips steps b to d, which use two model calls, and asks for the sentences in plainer words.
    func run(resumesAtSentences: Bool) async throws -> [String] {
        try session.printSetup()
        try await show("a-loaded", "a. the page as loaded")
        try await typeParagraph()
        if !resumesAtSentences {
            try await askForBlockers()
            try await accept()
            let accepted = page.lines
            try await askAndDiscard(equalTo: accepted)
        }
        try await askForSentences(resumesAtSentences ? Self.plainSentences : Self.sentences)
        try await removeFirstBlock()
        session.stop()
        return page.lines
    }

    private func show(_ name: String, _ title: String) async throws {
        print("\n== \(title)")
        for line in page.lines { print("  \(line)") }
        print("  proposal pending: \(page.proposal != nil)")
        let file = try await snapshot(
            pageOf: page, crew: session.app.crew, models: session.app.models, named: name,
            dark: false, size: CGSize(width: 1000, height: 1400), in: shots)
        print("  png: \(file.path)")
    }

    /// One model call. A request that makes no proposal is a failure, and the problem text the page shows is told.
    private func ask(_ request: String) async throws {
        asks += 1
        print("\nask \(asks): \(request)")
        let isProposed = await page.ask(request)
        try expect(
            isProposed, "the ask made a proposal", expected: "a proposal", found: page.problems.text ?? "no text")
        let proposal = try page.proposal.orFail("the page holds the proposal")
        print("  note: \(proposal.note)")
        for operation in proposal.operations { print("  operation: \(page.describe(operation))") }
        for refusal in page.refusals { print("  refused: \(refusal)") }
    }

    private func typeParagraph() async throws {
        let block = BlockID()
        try await page.store.saveNote(
            NoteChange(
                note: try NoteID(object: page.page).orFail("the page is a note"),
                blocks: [NoteBlock(id: block, text: Self.paragraph)], endings: [], order: [block]),
            owner: page.owner)
        page.refresh()
        try expect(
            page.paragraphs == [Self.paragraph], "the typed paragraph is on the page", expected: "[\(Self.paragraph)]",
            found: "\(page.paragraphs)")
        print("\ntyped one paragraph through the page model: \(Self.paragraph)")
    }

    private func askForBlockers() async throws {
        try await ask("Show the blockers.")
        try await show("b-pending-blockers", "b. pending proposal")
    }

    private func accept() async throws {
        await page.accept()
        try expect(page.proposal == nil, "accept clears the proposal", expected: "none", found: "still pending")
        try expect(
            page.problems.text == nil, "accept has no problem", expected: "none", found: page.problems.text ?? "")
        try await show("c-accepted", "c. after accept")
    }

    private func askAndDiscard(equalTo accepted: [String]) async throws {
        try await ask("Add a count of facts by person.")
        page.discard()
        try await show("d-discarded", "d. after discard")
        try expect(
            page.lines == accepted, "discard leaves the page as after step c", expected: "\(accepted)",
            found: "\(page.lines)")
    }

    private func askForSentences(_ request: String) async throws {
        let before = Set(page.textBlocks.map(\.text))
        try await ask(request)
        await page.accept()
        try await show("e-sentences", "e. after accept of the sentences")
        let added = page.textBlocks.filter { !before.contains($0.text) }
        try expect(!added.isEmpty, "the page has a new text block", expected: "one or more", found: "none")
        let loaded = Set(page.facts.compactMap(\.id))
        for block in added {
            print("  text: \(block.text)\n  cites: \(MachinePageModel.describe(block.cites))")
            let strangers = block.cites.compactMap { cite -> Int64? in
                if case .fact(let id) = cite, !loaded.contains(id) { id } else { nil }
            }
            try expect(
                strangers.isEmpty, "every cited fact was loaded", expected: "ids in \(loaded.sorted())",
                found: "\(strangers)")
        }
        print("  every fact cite is a loaded fact: yes (\(loaded.count) loaded)")
    }

    private func removeFirstBlock() async throws {
        let paragraphs = page.paragraphs
        let block = try page.firstMachineBlock.orFail("the page has a machine block to remove")
        try page.store.removeBlock(block, surface: .machinePage)
        page.refresh()
        try await show("f-removed", "f. after removing the first machine block")
        try expect(
            page.paragraphs == paragraphs, "the paragraphs are unchanged", expected: "\(paragraphs)",
            found: "\(page.paragraphs)")
    }

    /// The page of a store opened again must equal the page the first session left.
    func reopened(equalTo expected: [String]) async throws {
        try await show("g-reopened", "g. the store opened again")
        try expect(
            page.lines == expected, "the reopened page equals the page after step f", expected: "\(expected)",
            found: "\(page.lines)")
    }
}

extension Optional {
    func orFail(_ what: String) throws -> Wrapped {
        guard let self else { throw Expectation(what, expected: "a value", found: "nothing") }
        return self
    }
}

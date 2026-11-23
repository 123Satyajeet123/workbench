import Foundation
import Testing

@testable import WorkbenchCore

/// The editor's side of a note: which blocks keep their names, which are new and how each ended. Every edit is a
/// replaced range of the note's text; the document reads nothing else.
@Suite struct NoteDocumentTests {
    static let note = NoteID(project: "Bolt Pay")!

    /// A counter that gives each new block a name `n1`, `n2`, ... so a test reads the names.
    final class Names: @unchecked Sendable {
        private var count = 0
        func next() -> BlockID {
            count += 1
            return BlockID("n\(count)")!
        }
    }

    static func block(_ name: String, _ text: String) -> NoteBlock { NoteBlock(id: BlockID(name)!, text: text) }

    /// A document that holds these paragraphs as saved.
    static func saved(_ texts: [String]) -> NoteDocument {
        NoteDocument(note: note, stored: texts.enumerated().map { block("b\($0.offset + 1)", $0.element) })
    }

    static func ids(_ document: NoteDocument) -> [String] { document.blocks.map(\.id.rawValue) }
    static func texts(_ document: NoteDocument) -> [String] { document.blocks.map(\.text) }
    static func ending(_ change: NoteChange?) -> [BlockEnding] { change?.endings ?? [] }
    static func id(_ name: String) -> BlockID { BlockID(name)! }

    // MARK: A split keeps the old name for the first part

    @Test func returnInTheMiddleKeepsTheNameForTheFirstPartAndMakesANewBlockForTheRest() {
        let names = Names()
        var document = Self.saved(["Send the deck"])
        document.replace(4..<4, with: "\n", newID: names.next)
        #expect(Self.texts(document) == ["Send", " the deck"] && Self.ids(document) == ["b1", "n1"])
        let change = document.pendingChange()
        #expect(change?.blocks.map(\.id.rawValue) == ["b1", "n1"] && Self.ending(change).isEmpty)
        #expect(change?.order.map(\.rawValue) == ["b1", "n1"])
    }

    @Test func returnAtTheStartOfAParagraphMakesAnEmptyBlockBeforeItAndTheWordsKeepTheirName() {
        let names = Names()
        var document = Self.saved(["Send the deck"])
        document.replace(0..<0, with: "\n", newID: names.next)
        #expect(Self.texts(document) == ["", "Send the deck"] && Self.ids(document) == ["n1", "b1"])
        #expect(document.pendingChange() == nil, "the words did not change")
    }

    @Test func returnAtTheEndMakesAnEmptyBlockThatHasNoLineUntilItHasWords() {
        let names = Names()
        var document = Self.saved(["Send the deck"])
        document.replace(13..<13, with: "\n", newID: names.next)
        #expect(document.pendingChange() == nil)
        document.replace(14..<14, with: "Call Meera", newID: names.next)
        #expect(document.pendingChange()?.blocks.map(\.text) == ["Call Meera"])
    }

    // MARK: A merge is not a delete

    @Test func backspaceAtTheStartOfABlockMergesItIntoThePreviousOneAndErasesNothing() {
        var document = Self.saved(["Send the deck", "to Meera"])
        document.replace(13..<14, with: "")
        #expect(Self.texts(document) == ["Send the deckto Meera"] && Self.ids(document) == ["b1"])
        let change = document.pendingChange()
        #expect(change?.blocks == [Self.block("b1", "Send the deckto Meera")])
        #expect(change?.endings == [.merged(Self.id("b2"), into: Self.id("b1"))])
    }

    @Test func deletingTheLineBreakAtTheEndOfABlockMergesTheNextOneIntoIt() {
        var document = Self.saved(["One", "Two"])
        document.replace(3..<4, with: "")
        #expect(Self.ending(document.pendingChange()) == [.merged(Self.id("b2"), into: Self.id("b1"))])
    }

    @Test func backspaceAtTheStartOfABlockAfterAnEmptyOneDeletesTheEmptyBlockAndKeepsTheName() {
        let names = Names()
        var document = Self.saved(["Two"])
        document.replace(0..<0, with: "\n", newID: names.next)
        document.replace(0..<1, with: "", newID: names.next)
        #expect(Self.texts(document) == ["Two"] && Self.ids(document) == ["b1"])
        #expect(document.pendingChange() == nil)
    }

    @Test func backspaceAtTheStartOfAnEmptyBlockLeavesThePreviousBlockAlone() {
        var document = Self.saved(["One"])
        document.replace(3..<3, with: "\n")
        document.replace(3..<4, with: "")
        #expect(Self.texts(document) == ["One"] && document.pendingChange() == nil)
    }

    @Test func aMergedBlockNeverBecomesADeletedOne() {
        var document = Self.saved(["One", "Two", "Three"])
        document.replace(7..<8, with: "")
        let endings = Self.ending(document.pendingChange())
        #expect(endings == [.merged(Self.id("b3"), into: Self.id("b2"))])
        #expect(!endings.contains(.deleted(Self.id("b3"))))
    }

    // MARK: Deleting several blocks

    @Test func deletingSelectedBlocksEndsEachAsDeleted() {
        var document = Self.saved(["One", "Two", "Three", "Four"])
        document.replace(4..<14, with: "")
        #expect(Self.texts(document) == ["One", "Four"] && Self.ids(document) == ["b1", "b4"])
        let endings = Self.ending(document.pendingChange())
        #expect(Set(endings) == [.deleted(Self.id("b2")), .deleted(Self.id("b3"))])
        #expect(document.pendingChange()?.blocks.isEmpty == true, "the block after them did not change")
    }

    @Test func deletingTheWordsOfSeveralBlocksLeavesAnEmptyBlockWithANewName() {
        let names = Names()
        var document = Self.saved(["One", "Two", "Three", "Four"])
        document.replace(4..<13, with: "", newID: names.next)
        #expect(Self.texts(document) == ["One", "", "Four"] && Self.ids(document) == ["b1", "n1", "b4"])
        #expect(Set(Self.ending(document.pendingChange())) == [.deleted(Self.id("b2")), .deleted(Self.id("b3"))])
    }

    @Test func typingOverAWholeParagraphEndsItBecauseItsWordsAreGone() {
        let names = Names()
        var document = Self.saved(["One", "Two"])
        document.replace(0..<3, with: "Uno", newID: names.next)
        #expect(Self.ids(document) == ["n1", "b2"])
        #expect(Self.ending(document.pendingChange()) == [.deleted(Self.id("b1"))])
    }

    @Test func aSelectionThatEndsInsideABlockEndsItAsDeletedBecauseItsWordsWereRemoved() {
        var document = Self.saved(["One", "Two"])
        document.replace(1..<6, with: "")
        #expect(Self.texts(document) == ["Oo"])
        #expect(Self.ending(document.pendingChange()) == [.deleted(Self.id("b2"))])
        #expect(document.pendingChange()?.blocks.map(\.text) == ["Oo"])
    }

    @Test func removingAllTheWordsOfASavedBlockEndsItAndTheNextWordsGetANewName() {
        let names = Names()
        var document = Self.saved(["One"])
        document.replace(0..<3, with: "", newID: names.next)
        #expect(Self.ending(document.pendingChange()) == [.deleted(Self.id("b1"))])
        document.replace(0..<0, with: "Two", newID: names.next)
        #expect(document.pendingChange()?.blocks == [NoteBlock(id: Self.id("n1"), text: "Two")])
    }

    // MARK: Paste

    @Test func aPasteOfSeveralLinesMakesOneBlockForEachLine() {
        let names = Names()
        var document = Self.saved(["Start end"])
        document.replace(6..<6, with: "A\nB\nC", newID: names.next)
        #expect(Self.texts(document) == ["Start A", "B", "Cend"] && Self.ids(document) == ["b1", "n1", "n2"])
    }

    @Test func aPasteIntoAnEmptyNoteMakesBlocksWithNewNames() {
        let names = Names()
        var document = NoteDocument(note: Self.note)
        let first = document.blocks[0].id
        document.replace(0..<0, with: "One\nTwo", newID: names.next)
        #expect(Self.texts(document) == ["One", "Two"] && document.blocks[0].id == first)
        #expect(document.pendingChange()?.blocks.map(\.text) == ["One", "Two"])
    }

    @Test func aPasteOverSeveralBlocksEndsTheBlocksItReplacesAsDeleted() {
        let names = Names()
        var document = Self.saved(["One", "Two", "Three"])
        document.replace(0..<13, with: "X\nY", newID: names.next)
        #expect(Self.texts(document) == ["X", "Y"] && Set(Self.ids(document)).isDisjoint(with: ["b1", "b2", "b3"]))
        let endings = Self.ending(document.pendingChange())
        #expect(Set(endings) == [.deleted(Self.id("b1")), .deleted(Self.id("b2")), .deleted(Self.id("b3"))])
    }

    @Test func aBreakJoinedToAPasteMovesTheWordsToTheBlockThatHoldsThem() {
        let names = Names()
        var document = Self.saved(["One", "Two"])
        document.replace(3..<4, with: "\nmid\n", newID: names.next)
        #expect(Self.texts(document) == ["One", "mid", "Two"])
        #expect(Self.ending(document.pendingChange()) == [.merged(Self.id("b2"), into: Self.id("n2"))])
    }

    // MARK: Names across moves and edits

    @Test func aMoveKeepsTheNamesAndChangesTheOrder() {
        var document = Self.saved(["One", "Two", "Three"])
        document.move(Self.id("b3"), by: -2)
        #expect(Self.texts(document) == ["Three", "One", "Two"] && Self.ids(document) == ["b3", "b1", "b2"])
        let change = document.pendingChange()
        #expect(change?.blocks.isEmpty == true && change?.order.map(\.rawValue) == ["b3", "b1", "b2"])
    }

    @Test func aTypedEditKeepsTheNameAndIsOneChangedBlock() {
        var document = Self.saved(["One", "Two"])
        document.replace(3..<3, with: "!")
        #expect(document.pendingChange()?.blocks == [Self.block("b1", "One!")])
        #expect(Self.ending(document.pendingChange()).isEmpty)
    }

    @Test func aNoteThatTheStoreHoldsHasNothingToSave() {
        #expect(Self.saved(["One", "Two"]).pendingChange() == nil)
        #expect(NoteDocument(note: Self.note).pendingChange() == nil)
    }

    // MARK: A block the store never held

    @Test func aBlockThatWasNeverSavedLeavesNoEndingWhenItIsDeletedOrMerged() {
        let names = Names()
        var document = Self.saved(["One"])
        document.replace(3..<3, with: "\nTwo\nThree", newID: names.next)
        document.replace(4..<8, with: "", newID: names.next)
        document.replace(3..<4, with: "", newID: names.next)
        #expect(Self.ending(document.pendingChange()).isEmpty)
        #expect(document.pendingChange()?.blocks.map(\.text) == ["OneThree"])
    }

    @Test func aBlockMergedIntoAnUnsavedBlockThatMergedAgainFollowsTheChainToTheBlockThatHoldsItsWords() {
        let names = Names()
        var document = Self.saved(["One", "Two"])
        document.replace(3..<3, with: "\nNew", newID: names.next)
        document.replace(7..<8, with: "", newID: names.next)
        #expect(Self.texts(document) == ["One", "NewTwo"], "b2 joined the unsaved n1")
        document.replace(3..<4, with: "", newID: names.next)
        #expect(Self.texts(document) == ["OneNewTwo"])
        #expect(Self.ending(document.pendingChange()) == [.merged(Self.id("b2"), into: Self.id("b1"))])
    }

    @Test func aBlockMergedIntoABlockWhoseWordsWereThenRemovedEndsAsDeleted() {
        let names = Names()
        var document = Self.saved(["One", "Two"])
        document.replace(3..<4, with: "", newID: names.next)
        document.replace(0..<6, with: "", newID: names.next)
        #expect(Set(Self.ending(document.pendingChange())) == [.deleted(Self.id("b1")), .deleted(Self.id("b2"))])
    }

    // MARK: Saving while the person keeps typing

    @Test func editsMadeWhileASaveRunsStayPending() {
        var document = Self.saved(["One"])
        document.replace(3..<3, with: "A")
        let inFlight = document.pendingChange()!
        document.replace(4..<4, with: "B")
        document.didSave(inFlight)
        #expect(document.pendingChange()?.blocks == [Self.block("b1", "OneAB")])
        document.didSave(document.pendingChange()!)
        #expect(document.pendingChange() == nil)
    }

    @Test func aBlockEndedWhileItsFirstSaveRunsGetsItsEndingInTheNextChange() {
        let names = Names()
        var document = Self.saved(["One"])
        document.replace(3..<3, with: "\nTwo", newID: names.next)
        let inFlight = document.pendingChange()!
        document.replace(3..<7, with: "", newID: names.next)
        document.didSave(inFlight)
        #expect(Self.ending(document.pendingChange()) == [.deleted(Self.id("n1"))])
    }

    @Test func aBlockTheStoreRefusedGetsANewNameAndIsSavedAgain() {
        let names = Names()
        var document = Self.saved(["One"])
        document.replace(3..<3, with: "!")
        document.didSave(document.pendingChange()!)
        document.rename([Self.id("b1")], newID: names.next)
        #expect(document.pendingChange()?.blocks == [NoteBlock(id: Self.id("n1"), text: "One!")])
    }

    // MARK: Text

    @Test func devanagariAndEmojiSplitAndMergeAtTheirUTF16Offsets() {
        let names = Names()
        var document = Self.saved(["नमस्ते 👍 दुनिया"])
        let offset = "नमस्ते 👍".utf16.count
        document.replace(offset..<offset, with: "\n", newID: names.next)
        #expect(Self.texts(document) == ["नमस्ते 👍", " दुनिया"])
        document.replace(offset..<(offset + 1), with: "", newID: names.next)
        #expect(Self.texts(document) == ["नमस्ते 👍 दुनिया"])
    }

    @Test func aRangeThatEndsPastTheTextIsKeptInsideTheNote() {
        var document = Self.saved(["One"])
        document.replace(1..<99, with: "")
        #expect(Self.texts(document) == ["O"])
    }

    @Test func theTextOfTheDocumentFollowsEveryEditLikeAPlainString() {
        let names = Names()
        var document = Self.saved(["alpha", "beta", "gamma"])
        let plain = NSMutableString(string: document.text)
        var generator = SeededGenerator(seed: 7)
        let pieces = ["", "x", "\n", "yz\nw", "नमस्ते", "👍\n👍", "\n\n"]
        for _ in 0..<400 {
            let length = plain.length
            let start = Int.random(in: 0...length, using: &generator)
            let end = Int.random(in: start...min(length, start + 6), using: &generator)
            let replacement = pieces.randomElement(using: &generator)!
            guard Self.isOnBoundary(plain as String, start), Self.isOnBoundary(plain as String, end) else { continue }
            plain.replaceCharacters(in: NSRange(location: start, length: end - start), with: replacement)
            document.replace(start..<end, with: replacement, newID: names.next)
            #expect(document.text == plain as String)
        }
    }

    @Test func aThousandBlocksTakeAnEditInWellUnderAMillisecond() {
        let names = Names()
        var document = Self.saved((0..<1000).map { "Paragraph \($0)" })
        let clock = ContinuousClock()
        let spent = clock.measure {
            for index in 0..<200 { document.replace(index * 12..<index * 12, with: "x", newID: names.next) }
        }
        #expect(spent < .milliseconds(200), "200 edits took \(spent)")
        #expect(document.pendingChange()?.order.count == 1000)
    }

    static func isOnBoundary(_ text: String, _ offset: Int) -> Bool {
        let units = Array(text.utf16)
        guard offset > 0, offset < units.count else { return true }
        return !(UTF16.isTrailSurrogate(units[offset]) && UTF16.isLeadSurrogate(units[offset - 1]))
    }
}

struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

extension NoteDocumentTests {
    @Test func aNoteDeletedElsewhereLeavesTheDocumentButWhatWasWrittenSinceStays() {
        var document = Self.saved(["One", "Two"])
        document.replace(7..<7, with: "!")
        document.replace(3..<3, with: "\nNew", newID: Names().next)
        document.drop(document.savedBlocks)
        #expect(Self.texts(document) == ["New", "Two!"])
        #expect(document.pendingChange()?.blocks.map(\.text) == ["New", "Two!"])
        #expect(document.pendingChange()?.endings.isEmpty == true)
    }

    @Test func aNoteDeletedElsewhereLeavesOneEmptyBlockToWriteIn() {
        var document = Self.saved(["One"])
        document.drop(document.savedBlocks)
        #expect(Self.texts(document) == [""] && document.pendingChange() == nil)
    }

    @Test func theTextOffsetOfABlockAndTheBlockAtAnOffsetAgree() {
        let document = Self.saved(["One", "नमस्ते", "👍"])
        #expect(document.offset(of: Self.id("b3")) == 4 + 7)
        #expect(document.blockID(at: 5) == Self.id("b2") && document.blockID(at: 11) == Self.id("b3"))
    }
}

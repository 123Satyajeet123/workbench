import Foundation
import GRDB
import Lines
import Testing

@testable import WorkbenchCore

/// M1 step 2b: the lines a run read are kept as `run_window` rows, a proof card resolves an item's cite number through
/// them, and a revoke or an erase reaches them.
@Suite struct RunWindowTests {
    static let chat = EvidenceIngestTests.chat
    static let from = Date(timeIntervalSince1970: 1_794_000_000)
    static let to = Date(timeIntervalSince1970: 1_796_000_000)

    /// A world with two messages stored, and a run that read both.
    struct Scene {
        let world: EvidenceIngestTests.World
        let run: RunID
        let numbers: [Int64]

        init(_ texts: [String] = ["login done", "shipped the build"]) throws {
            world = try EvidenceIngestTests.World()
            _ = try world.record(try texts.enumerated().map { try EvidenceIngestTests.message($1, stanza: "m\($0)") })
            let lines = try world.store.queries.currentLines(in: [RunWindowTests.chat], from: from, to: to)
            numbers = lines.map(\.number)
            run = try world.store.beginRun(
                task: "t", model: "m", prompt: "p", input: "x", kinds: [.whatsapp],
                window: lines.map { WindowLine(number: $0.number, lineID: $0.lineID) })
        }

        func item(cite number: Int64) -> Item {
            Item(
                task: "t", day: WorkDay(containing: RunWindowTests.from), scope: RunWindowTests.chat, source: .whatsapp,
                citeFirst: number, citeLast: number, start: RunWindowTests.from, end: RunWindowTests.from, fields: [:],
                quote: "q", run: run)
        }

        func proof(of item: Item, reach: Int = 0) throws -> [ProofLine] {
            try world.store.queries.proofLines(of: item, reach: reach)
        }
    }

    @Test func aRunKeepsTheLinesItsInputShowedUnderTheirNumbers() throws {
        let scene = try Scene()
        let window = try scene.world.store.queries.window(of: scene.run)
        #expect(window.map(\.text) == ["login done", "shipped the build"])
        #expect(window.map(\.number) == scene.numbers)
    }

    @Test func currentLinesKeepTheLatestVersionOfEachMessageAndTheTombstonesInsideTheDay() throws {
        let scene = try Scene()
        scene.world.advance(by: 60)
        _ = try scene.world.record([try EvidenceIngestTests.message("login done, fixed", stanza: "m0")], row: 101)
        _ = try scene.world.record([try EvidenceIngestTests.revoke(stanza: "m1")], row: 102)
        let store = scene.world.store.queries
        #expect(
            try store.currentLines(in: [Self.chat], from: Self.from, to: Self.to).map(\.text) == [
                "login done, fixed", "",
            ])
        #expect(
            try store.currentLines(in: [Self.chat], from: Self.from, to: Self.to).map(\.isTombstone) == [false, true])
        #expect(try store.currentLines(in: [Self.chat], from: Self.to, to: Self.to.addingTimeInterval(1)).isEmpty)
        #expect(try store.currentLines(in: ["other@g.us"], from: Self.from, to: Self.to).isEmpty)
    }

    @Test func aProofCardShowsTheSameQuoteAfterTheMessageWasEdited() throws {
        let scene = try Scene()
        let item = scene.item(cite: scene.numbers[0])
        scene.world.advance(by: 60)
        _ = try scene.world.record([try EvidenceIngestTests.message("login NOT done", stanza: "m0")], row: 101)
        let now = try scene.world.store.queries.currentLines(in: [Self.chat], from: Self.from, to: Self.to)
        #expect(
            now.map(\.text).contains("login NOT done") && !now.map(\.text).contains("login done"), "the source changed")
        #expect(try scene.proof(of: item).map(\.line.text) == ["login done"], "the proof did not")
    }

    @Test func aRevokedLineShowsAsDeletedWithItsTimeAndSenderAndNoWordsAnywhere() throws {
        let word = EvidenceIngestTests.word()
        let scene = try Scene([word, "other"])
        let item = scene.item(cite: scene.numbers[0])
        #expect(try scene.world.copies(of: word) > 0)
        _ = try scene.world.record([try EvidenceIngestTests.revoke(stanza: "m0")], row: 101)
        let proof = try #require(try scene.proof(of: item).first)
        #expect(proof.line.isTombstone && proof.line.text.isEmpty && proof.isCited)
        #expect(proof.line.actor == EvidenceIngestTests.member && proof.line.time != nil)
        #expect(try scene.world.copies(of: word) == 0, "the words are gone from the file and its log")
        #expect(try scene.world.count("SELECT count(*) FROM run_window WHERE run_id = \(scene.run)") == 2)
    }

    @Test func aRevokeMovesEveryVersionsPlaceToTheTombstone() throws {
        let scene = try Scene(["first"])
        scene.world.advance(by: 60)
        _ = try scene.world.record([try EvidenceIngestTests.message("second", stanza: "m0")], row: 101)
        let second = try scene.world.store.queries.currentLines(in: [Self.chat], from: Self.from, to: Self.to)[0]
        let later = try scene.world.store.beginRun(
            task: "t", model: "m", prompt: "p", input: "y", kinds: [.whatsapp],
            window: [WindowLine(number: second.number, lineID: second.lineID)])
        _ = try scene.world.record([try EvidenceIngestTests.revoke(stanza: "m0")], row: 102)
        for run in [scene.run, later] {
            let lines = try scene.world.store.queries.window(of: run)
            #expect(lines.count == 1 && lines[0].isTombstone, "run \(run) shows the deletion")
        }
    }

    @Test func anItemMadeBeforeRunsKeptWindowsResolvesThroughTheOldCitationIds() throws {
        let world = try EvidenceIngestTests.World()
        _ = try world.record(
            [
                try EvidenceIngestTests.message("before", stanza: "a", legacy: 120),
                try EvidenceIngestTests.message("the cited one", stanza: "b", legacy: 121),
                try EvidenceIngestTests.message("after", stanza: "c", legacy: 122),
                try EvidenceIngestTests.message("far", stanza: "d", legacy: 130),
            ], mapsLegacyRefs: true)
        let run = try world.store.beginRun(task: "t", model: "m", prompt: "p", input: "x", kinds: [.whatsapp])
        var item = Scene.legacyItem(cite: 121, run: run)
        let proof = try world.store.queries.proofLines(of: item, reach: 1)
        #expect(proof.map(\.line.text) == ["before", "the cited one", "after"])
        #expect(proof.map(\.isCited) == [false, true, false])
        _ = try world.record([try EvidenceIngestTests.revoke(stanza: "b", legacy: nil)], row: 101)
        let revoked = try world.store.queries.proofLines(of: item, reach: 0)
        #expect(revoked.map(\.line.isTombstone) == [true], "an old citation of a deleted message shows the tombstone")
        item.scope = "other@g.us"
        #expect(
            try world.store.queries.proofLines(of: item, reach: 1).isEmpty, "another chat's rows are not this fact's")
    }

    @Test func aFactThatCitesNoLineHasNoProof() throws {
        let scene = try Scene()
        #expect(try scene.proof(of: scene.item(cite: 0)).isEmpty)
    }

    @Test func reachAddsTheLinesAroundTheCitedOnesByPosition() throws {
        let scene = try Scene(["one", "two", "three", "four", "five"])
        let item = scene.item(cite: scene.numbers[2])
        #expect(try scene.proof(of: item, reach: 1).map(\.line.text) == ["two", "three", "four"])
        #expect(try scene.proof(of: item, reach: 0).map(\.line.text) == ["three"])
    }

    // MARK: Which lines a machine has read

    @Test func aLineCountsAsReadOnlyWhenALiveReadingThatUsedItWasSaved() throws {
        let scene = try Scene()
        let store = scene.world.store
        #expect(
            try store.queries.numbersRead(by: "t", among: scene.numbers).isEmpty, "the model answered, nothing saved")
        try store.recordYield(of: scene.run, kept: 0, dropped: 0)
        #expect(try store.queries.numbersRead(by: "t", among: scene.numbers) == Set(scene.numbers))
        #expect(try store.queries.numbersRead(by: "t", among: [scene.numbers[0]]) == [scene.numbers[0]])
        #expect(try store.queries.numbersRead(by: "other", among: scene.numbers).isEmpty, "another machine's lines")
    }

    @Test func aTrialRunOfTheSameMachineLeavesTheLinesUnread() throws {
        let world = try EvidenceIngestTests.World()
        _ = try world.record([try EvidenceIngestTests.message("login done", stanza: "m0")])
        let lines = try world.store.queries.currentLines(in: [Self.chat], from: Self.from, to: Self.to)
        let trial = try world.store.beginRun(
            task: Trial.task(of: "t"), model: "m", prompt: "p", input: "x", kinds: [.whatsapp],
            window: lines.map { WindowLine(number: $0.number, lineID: $0.lineID) })
        try world.store.recordYield(of: trial, kept: 1, dropped: 0)
        #expect(try world.store.queries.numbersRead(by: "t", among: lines.map(\.number)).isEmpty)
        #expect(try world.store.queries.numbersRead(by: Trial.task(of: "t"), among: lines.map(\.number)).count == 1)
    }

    // MARK: The guards of the table

    @Test func aWindowRowNeverChangesExceptToItsMessagesTombstone() throws {
        let scene = try Scene()
        let store = scene.world.store
        let first = try store.queries.window(of: scene.run)[0]
        func attempt(_ sql: String) -> Bool {
            (try? store.writer.write { try $0.execute(sql: sql) }) != nil
        }
        #expect(!attempt("UPDATE run_window SET ordinal = 999 WHERE run_id = \(scene.run)"))
        #expect(!attempt("UPDATE run_window SET run_id = 999 WHERE run_id = \(scene.run)"))
        let other = try store.queries.window(of: scene.run)[1].lineID.hexString
        #expect(!attempt("UPDATE run_window SET line_id = x'\(other)' WHERE ordinal = \(first.number)"), "a text line")
        #expect(
            !attempt(
                "INSERT INTO run_window(run_id, ordinal, line_id) VALUES (\(scene.run), \(first.number), x'\(other)')"),
            "another line under a used number")
        #expect(
            attempt(
                "INSERT INTO run_window(run_id, ordinal, line_id) VALUES (\(scene.run), \(first.number), x'\(first.lineID.hexString)')"
            ),
            "the same row again does nothing")
        #expect(try scene.world.count("SELECT count(*) FROM run_window") == 2)
    }

    @Test func aTombstoneOfAnotherChatIsNotAPlaceForALine() throws {
        let scene = try Scene()
        let store = scene.world.store
        let other = "999@g.us"
        try store.savePolicy(
            CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [Self.chat, other]]))
        _ = try scene.world.record(
            [
                ObservedLine(
                    line: .tombstone(entity: try EvidenceIngestTests.entity("z", chat: other), readerVersion: "t"),
                    eventTime: UTCInstant(milliseconds: 1_795_000_000_000), actor: EvidenceIngestTests.member)
            ], chat: other)
        let tombstone = try store.writer.read {
            try Data.fetchOne(
                $0, sql: "SELECT line_id FROM evidence WHERE container = ? AND tombstone = 1", arguments: [other])
        }
        let hex = try #require(tombstone).hexString
        #expect((try? store.writer.write { try $0.execute(sql: "UPDATE run_window SET line_id = x'\(hex)'") }) == nil)
    }

    // MARK: Erase

    @Test func aSettingsDeleteOfOldDataRemovesTheWindowRowsOfErasedLinesAndKeepsTheRun() throws {
        let scene = try Scene()
        let store = scene.world.store
        try store.delete(.everything(before: Self.to))
        #expect(try scene.world.count("SELECT count(*) FROM evidence") == 0)
        #expect(try scene.world.count("SELECT count(*) FROM run_window") == 0)
        #expect(try scene.world.count("SELECT count(*) FROM run WHERE id = \(scene.run)") == 1, "the meter stays")
    }

    @Test func aSettingsDeleteOfWhatsAppRemovesTheWindowRowsOfItsLinesAndNoOthers() throws {
        let scene = try Scene()
        try scene.world.store.delete(.kind(.whatsapp, before: nil))
        #expect(try scene.world.count("SELECT count(*) FROM run_window") == 0)
    }

    @Test func aDeleteOfAnotherKindKeepsTheWindowRows() throws {
        let scene = try Scene()
        try scene.world.store.delete(.kind(.mail, before: nil))
        #expect(try scene.world.count("SELECT count(*) FROM run_window") == 2)
    }

    // MARK: The step

    @Test func theStepMakesAStrictTableAndAnEarlierStoreGainsItWithoutLosingData() throws {
        let store = try makeStore()
        let strict = try store.writer.read { db in
            try Row.fetchAll(db, sql: "PRAGMA table_list").first { ($0["name"] as String) == "run_window" }?["strict"]
                as Int?
        }
        #expect(strict == 1)
        #expect(Schema.steps.contains(Schema.runWindow))
    }
}

extension RunWindowTests.Scene {
    static func legacyItem(cite number: Int64, run: RunID) -> Item {
        Item(
            task: "t", day: WorkDay(containing: RunWindowTests.from), scope: RunWindowTests.chat, source: .whatsapp,
            citeFirst: number, citeLast: number, start: RunWindowTests.from, end: RunWindowTests.from, fields: [:],
            quote: "q", run: run)
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

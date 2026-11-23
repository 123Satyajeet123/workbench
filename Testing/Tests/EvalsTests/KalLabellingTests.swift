import Foundation
import SQLite3
import Testing

@testable import Evals
@testable import WorkbenchCore

/// The labelling tool for probe P-F4, on made-up lines.
@Suite struct KalLabellingTests {
    struct Lines: LabelLineSource {
        var byDay: [String: [LabelLine]] = [:]

        func lines(on day: WorkDay) throws -> [LabelLine] { byDay[day.description] ?? [] }
    }

    private static func day(_ text: String) -> WorkDay { WorkDay(text)! }

    private static func week(from first: String) -> [WorkDay] { (0..<7).map { day(first).adding(days: $0) } }

    /// Two lines with a term and two without, on each given day.
    private static func source(_ days: [WorkDay]) -> Lines {
        Lines(
            byDay: Dictionary(
                uniqueKeysWithValues: days.map { day in
                    let text = day.description
                    return (
                        text,
                        [
                            LabelLine(day: day, id: "a-\(text)", text: "Asha: Kal deck bhej dunga"),
                            LabelLine(day: day, id: "b-\(text)", text: "Raj: lunch?"),
                            LabelLine(day: day, id: "c-\(text)", text: "Raj: parson mila tha, ok"),
                            LabelLine(day: day, id: "d-\(text)", text: "Raj: kalam is a pen"),
                        ]
                    )
                }))
    }

    private static func isDev(_ day: WorkDay) -> Bool { EvalSplit(day) == .dev }

    /// The first day from 2026-10-01 on that the hash split holds out, and the first it keeps.
    private static let splitHeldOut = (0..<60).map { day("2026-10-01").adding(days: $0) }.first { !isDev($0) }!
    private static let devDay = (0..<60).map { day("2026-10-01").adding(days: $0) }.first(where: isDev)!

    private let terms = ["kal", "parson"]

    @Test func itShowsOnlyTheLinesThatHoldAWholeTermOfTheDevDaysInDayOrder() throws {
        let days = Self.week(from: "2026-11-02")
        let tool = KalLabelling(source: Self.source(days), terms: terms)
        let lines = try tool.candidates(weekStarting: Self.day("2026-11-02"))
        let dev = days.filter(Self.isDev)
        #expect(!dev.isEmpty && dev.count < days.count, "the week has both kinds of day")
        #expect(lines.map(\.id) == dev.flatMap { ["a-\($0)", "c-\($0)"] })
        #expect(!lines.contains { $0.text.contains("kalam") || $0.text.contains("lunch") })
    }

    @Test func itAsksOnceForEachLineAndRecordsThePastOrFutureTheFounderGives() throws {
        let start = Self.devDay
        let tool = KalLabelling(source: Self.source([start]), terms: terms)
        var asked: [String] = []
        var written: [LabelRecord] = []
        let answers: [LabelAnswer] = [.label(.future), .skip]
        var next = 0
        let count = try tool.run(
            weekStarting: start,
            ask: { line, number, total in
                asked.append("\(number)/\(total) \(line.id)")
                defer { next += 1 }
                return answers[next]
            }, record: { written.append($0) })
        #expect(asked == ["1/2 a-\(start)", "2/2 c-\(start)"] && count == 1)
        #expect(written == [LabelRecord(day: start.description, line: "a-\(start)", label: .future)])
        #expect(!written[0].jsonLine.contains("deck"), "the words are never written")
    }

    @Test func quittingStopsTheAskingAndKeepsTheLabelsGiven() throws {
        let tool = KalLabelling(source: Self.source([Self.devDay]), terms: terms)
        var written: [LabelRecord] = []
        var next = 0
        let answers: [LabelAnswer] = [.label(.past), .quit]
        let count = try tool.run(
            weekStarting: Self.devDay,
            ask: { _, _, _ in
                defer { next += 1 }
                return answers[next]
            },
            record: { written.append($0) })
        #expect(count == 1 && written.map(\.label) == [.past])
    }

    @Test func aWeekThatTouchesTheHeldOutRangeIsRefusedBeforeAnyLineIsShown() throws {
        let tool = KalLabelling(
            source: Self.source(Self.week(from: "2026-11-17") + Self.week(from: "2026-12-01")), terms: terms)
        var shown = 0
        for start in ["2026-11-23", "2026-12-01", "2026-11-22", "2026-12-06", "2026-11-17"] {
            #expect(throws: HeldOutDays.Refused.self, "\(start)") {
                try tool.run(
                    weekStarting: Self.day(start),
                    ask: { _, _, _ in
                        shown += 1
                        return .skip
                    }, record: { _ in })
            }
        }
        #expect(shown == 0)
    }

    @Test func aWeekClearOfTheRangeIsNotRefused() throws {
        for start in ["2026-11-16", "2026-12-07"] {
            let days = Self.week(from: start)
            let tool = KalLabelling(source: Self.source(days), terms: terms)
            #expect(try tool.candidates(weekStarting: Self.day(start)).count == 2 * days.filter(Self.isDev).count)
        }
        #expect(HeldOutDays.founder.days.contains(Self.day("2026-11-23")))
        #expect(HeldOutDays.founder.days.contains(Self.day("2026-12-06")))
        #expect(!HeldOutDays.founder.days.contains(Self.day("2026-11-22")))
        #expect(!HeldOutDays.founder.days.contains(Self.day("2026-12-07")))
    }

    @Test func aDayTheHashSplitHoldsOutIsNeverShownOrWritten() throws {
        let held = Self.splitHeldOut
        let tool = KalLabelling(source: Self.source([held, Self.devDay]), terms: terms)
        #expect(EvalSplit(held) == .heldOut && EvalSplit(Self.devDay) == .dev)
        #expect(try tool.candidates(weekStarting: held).isEmpty, "no source line of a held-out day")
        var written: [LabelRecord] = []
        let lying = Lines(byDay: [Self.devDay.description: Self.source([held]).byDay[held.description]!])
        try KalLabelling(source: lying, terms: terms).run(
            weekStarting: Self.devDay, ask: { _, _, _ in .label(.past) }, record: { written.append($0) })
        #expect(written.isEmpty, "a line of a held-out day is dropped even when the source gives it under a dev day")
        let own = try KalLabelling(source: Self.source([Self.devDay]), terms: terms).candidates(
            weekStarting: Self.devDay)
        #expect(own.count == 2, "a dev day is shown")
    }

    // MARK: the store is read from a copy

    private func versionOf(_ file: URL) -> Int32 {
        var handle: OpaquePointer?
        sqlite3_open_v2(file.path, &handle, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(handle, "PRAGMA user_version", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        sqlite3_step(statement)
        return sqlite3_column_int(statement, 0)
    }

    /// A store one step older than this version, as a shipped app would have left it.
    private func olderStore() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "kal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "workbench.sqlite")
        var handle: OpaquePointer?
        #expect(sqlite3_open(file.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        let before = try #require(Schema.steps.firstIndex(of: Schema.timers))
        for statement in Schema.steps.prefix(before).joined() {
            #expect(sqlite3_exec(handle, statement, nil, nil, nil) == SQLITE_OK)
        }
        sqlite3_exec(handle, "PRAGMA user_version = \(before)", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA journal_mode = DELETE", nil, nil, nil)
        return folder
    }

    @Test func aRunReadsACopyAndLeavesTheOriginalStoreUntouched() throws {
        let folder = try olderStore()
        let file = folder.appending(path: "workbench.sqlite")
        let bytes = try Data(contentsOf: file)
        let version = versionOf(file)
        var copyVersion: Int32?
        let count = try Store.withCopy(of: folder) { store in
            copyVersion = versionOf(store.directory.appending(path: "workbench.sqlite"))
            return try KalLabelling(source: StoreLines(store: store, chats: ["x"]), terms: terms)
                .candidates(weekStarting: Self.devDay).count
        }
        #expect(count == 0)
        #expect(copyVersion == Int32(Schema.steps.count), "the copy was opened, so it was migrated")
        #expect(try Data(contentsOf: file) == bytes && versionOf(file) == version, "the original is as it was")
        let ran = try KalLabelling.run(
            onCopyOf: folder, chats: ["x"], terms: terms, weekStarting: Self.devDay, ask: { _, _, _ in .skip },
            record: { _ in })
        let after = try Data(contentsOf: file)
        #expect(ran == 0 && after == bytes && versionOf(file) == version)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "workbench.sqlite-wal").path))
    }

    @Test func theCopyIsDeletedWhenTheRunEnds() throws {
        let folder = try olderStore()
        var copy: URL?
        try Store.withCopy(of: folder) { copy = $0.directory }
        #expect(!FileManager.default.fileExists(atPath: try #require(copy).path))
    }
}

import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// The time field of Pip: what the model is asked, what an existing machine keeps doing, how a "kal" line reaches
/// Today, and what the schema step does to the due days a store already holds.
@Suite struct TimeFieldTests {
    /// Pip as an existing machine holds it: the free-text `eta` field in place of the time field.
    private var machineBeforeTheTimeField: HelperSpec {
        var spec = HelperSpec.team
        spec.fields = spec.fields.map {
            $0.kind == .time ? .init("eta", .text(required: false), meaning: "The date it is due.") : $0
        }
        return spec
    }

    private func reader(_ spec: HelperSpec) throws -> HelperReader {
        HelperReader(spec: spec, model: RecordedModel(ScriptedModel("{}"), store: try makeStore()))
    }

    @Test func theBuiltInMachineAsksForAClosedRecordAndNeverForADate() throws {
        let instructions = try reader(.team).instructions
        #expect(instructions.contains("- when: an object. Always give every part. direction: past, future or unclear."))
        #expect(instructions.contains("Never write a date."))
        #expect(!instructions.contains("YYYY-MM-DD"))
        let schema = try reader(.team).schema
        let item = pipItem(when: TimeJSON.inDays(1, words: "kal"), cite: 1, quote: "q")
        #expect(schema.accepts(json: pipReply([item])))
        let asDate = item.replacingOccurrences(of: TimeJSON.inDays(1, words: "kal"), with: #""2026-11-23""#)
        #expect(!schema.accepts(json: pipReply([asDate])), "a date in place of the record is not accepted")
        let noBoolean = item.replacingOccurrences(of: #""ambiguous":false"#, with: #""ambiguous":"no""#)
        #expect(!schema.accepts(json: pipReply([noBoolean])))
    }

    @Test func theModelIsToldTheWeekdayOfTheWorkDay() {
        let input = HelperReader.input(day: Days.first, evidence: EvidenceSet(lines: []))
        #expect(input.contains("Work day: \(Days.first) (\(Days.first.weekdayName))"))
        #expect(
            ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"].contains(
                Days.first.weekdayName))
    }

    @Test func theNewDesignIsANewPromptVersionAndTheOldMachineIsOfferedTheUpdate() throws {
        let old = try reader(machineBeforeTheTimeField)
        let new = try reader(.team)
        #expect(old.instructions != new.instructions)
        #expect(try old.schema.jsonText != new.schema.jsonText)
        let changes = try #require(machineBeforeTheTimeField.update(toward: .team))
        #expect(changes == ["reads when a fact is due, as a day and part of day", "drops eta"])
    }

    @Test func aMachineMadeBeforeTheTimeFieldKeepsReadingItsEtaAsTextAndGivesNoDueTime() async throws {
        let world = try LifecycleWorld()
        let old = machineBeforeTheTimeField
        let reply = pipReply([
            pipItem(cite: 1, quote: "send the deck").replacingOccurrences(
                of: #""when":"# + TimeJSON.none, with: #""eta":"Fri 25 Sep""#)
        ])
        let reader = HelperReader(spec: old, model: RecordedModel(ScriptedModel(reply), store: world.store))
        let evidence = EvidenceSet(
            lines: [world.line(1, Days.first, 600, "I will send the deck by Friday")], context: LifecycleWorld.members)
        let result = try await reader.read(day: Days.first, scope: "work", evidence: evidence)
        let item = try #require(result.items.first)
        #expect(result.dropped == 0 && item["eta"] == "Fri 25 Sep" && item.due == nil)
    }

    @Test func aKalLineIsDueTheNextWorkDayOnTodayAndNotBefore() async throws {
        let world = try LifecycleWorld()
        try await world.read(
            [pipItem(when: TimeJSON.inDays(1, words: "kal tak"), cite: 1, quote: "bhej dunga")],
            lines: [world.line(1, Days.first, 600, "deck kal tak bhej dunga")])
        let open = try world.open()
        #expect(open.first?.dueDay == Days.second)
        let before = pickedNeeds(facts: open, now: Days.at(Days.first, 700))
        #expect(before.map(\.reason) == [.waiting], "not slipped before its day")
        let onTheDay = pickedNeeds(facts: open, now: Days.at(Days.second, 700))
        #expect(onTheDay.map(\.reason) == [.waiting], "due later that day: not slipped yet")
        let after = pickedNeeds(facts: open, now: Days.at(Days.second.adding(days: 1), 0))
        #expect(after.map(\.reason) == [.due(Days.second)], "slipped once the day is over")
    }

    @Test func aPastKalOrAnAmbiguousOneNeverMakesAFactDue() async throws {
        let world = try LifecycleWorld()
        let past = TimeJSON.record("past", offset: -1, precision: "day", words: "kal")
        let ambiguous = TimeJSON.record("future", offset: 1, precision: "day", ambiguous: true, words: "kal")
        try await world.read(
            [
                pipItem(when: past, cite: 1, quote: "bheja tha"),
                pipItem("commitment", "Send the plan", when: ambiguous, cite: 2, quote: "bhej dunga"),
            ],
            lines: [
                world.line(1, Days.first, 600, "deck kal bheja tha"),
                world.line(2, Days.first, 610, "plan kal bhej dunga"),
            ])
        let open = try world.open()
        #expect(open.count == 2 && open.allSatisfy { $0.dueDay == nil })
        #expect(open.allSatisfy { $0.openedDue?.record != nil }, "the record stays")
        #expect(try open.allSatisfy { try world.store.queries.timers(of: $0.id!).isEmpty })
    }

    // MARK: the schema step

    private func storeBeforeTheStep() throws -> URL {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: folder.appending(path: "workbench.sqlite").path)
        try queue.write { db in
            let before = try #require(Schema.steps.firstIndex(of: Schema.timers))
            for statement in Schema.steps.prefix(before).joined() { try db.execute(sql: statement) }
            try db.execute(sql: "PRAGMA user_version = \(before)")
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', '2026-11-19T10:00:00Z', '2026-11-19T10:00:01Z', 'done')
                    """)
            for (number, eta) in ["2026-11-25", "2026-11-26", "kal tak", ""].enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at,
                            fields, quote, created_at) VALUES ('t', 1, '2026-11-19', '', 'whatsapp', \(number + 10),
                            \(number + 10), '2026-11-19T10:00:00Z', '2026-11-19T11:00:00Z',
                            json_object('kind', 'plan', 'eta', ?), 'q\(number)', '2026-11-19T12:00:00Z')
                        """, arguments: [eta])
            }
            try db.execute(
                sql: """
                    INSERT INTO item_event(item_id, kind, outcome, line_id, quote, valid_at, recorded_at, run_id, actor)
                    VALUES (2, 'close', 'kept', NULL, NULL, '2026-11-20T10:00:00Z', '2026-11-20T10:00:00Z', NULL,
                        'person')
                    """)
        }
        return folder
    }

    @Test func theStepMovesADueDayFromEtaIntoTheDueFieldAndArmsATimerForEachOpenFact() throws {
        let store = try Store(
            directory: storeBeforeTheStep(), ownerZone: try #require(TimeZone(identifier: "Asia/Kolkata")))
        let items = try store.queries.items(of: "t", since: try #require(WorkDay("2026-11-19")))
        #expect(items.map(\.dueDay) == [WorkDay("2026-11-25"), WorkDay("2026-11-26"), nil, nil])
        #expect(items[0].openedDue?.source == .stated && items[0].openedDue?.zone == "Asia/Kolkata")
        #expect(items[0].openedDue?.zoneAssumed == true, "the zone came from the migration")
        #expect(items[0].openedDue?.utc == ISO8601DateFormatter().date(from: "2026-11-25T18:29:59Z"))
        #expect(items.map { $0["eta"] } == ["2026-11-25", "2026-11-26", "kal tak", ""], "the old text stays")
        #expect(try store.queries.timers(of: 1).map(\.isCancelled) == [false])
        #expect(try store.queries.timers(of: 2).isEmpty, "a closed fact gets no timer")
        #expect(try store.queries.timers(of: 3).isEmpty && store.queries.timers(of: 4).isEmpty)
    }

    @Test func theMigrationUsesTheOwnersZoneAndTheTimerFiresAtTheEndOfTheDayThere() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let store = try Store(directory: storeBeforeTheStep(), ownerZone: zone)
        let since = try #require(WorkDay("2026-11-19"))
        let due = try #require(try store.queries.items(of: "t", since: since).first?.openedDue)
        #expect(due.zone == "America/New_York" && due.zoneAssumed == true)
        #expect(
            due.utc == ISO8601DateFormatter().date(from: "2026-11-26T04:59:59Z"), "23:59:59 in New York in November")
        let timer = try #require(try store.queries.timers(of: 1).first)
        #expect(timer.zone == "America/New_York" && timer.fireAt == due.utc)
    }

    @Test func aDueTheModelOrAPersonSetCarriesNoMigrationMark() async throws {
        let world = try LifecycleWorld()
        try await world.read(
            [pipItem(when: TimeJSON.inDays(1, words: "kal"), cite: 1, quote: "bhej")],
            lines: [world.line(1, Days.first, 600, "deck kal bhej")])
        #expect(try world.open().first?.openedDue?.zoneAssumed == nil)
        #expect(Due.stated(on: Days.first).zoneAssumed == nil)
    }

    @Test func aStoreAtTheLatestStepIsNotChangedAgain() throws {
        let folder = try storeBeforeTheStep()
        let first = try Store(directory: folder)
        let before = try first.queries.timers(of: 1)
        let again = try Store(directory: folder)
        #expect(try again.queries.timers(of: 1) == before)
    }
}

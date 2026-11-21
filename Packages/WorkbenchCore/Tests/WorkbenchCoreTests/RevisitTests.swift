import Foundation
import Testing

@testable import WorkbenchCore

/// The passed-deal watch and the news that reaches Today.
@Suite struct RevisitTests {
    private let due = WorkDay(containing: day(180))

    private func needs(_ store: Store, on date: Date) throws -> [Need] {
        Needs.pick(
            facts: [], findings: [], today: WorkDay(containing: date), now: date,
            revisits: try store.queries.openRevisits(), news: try store.queries.newsSignals())
    }

    @Test func theDefaultRevisitIsSixMonthsAfterThePass() {
        let pass = WorkDay(containing: t0).start.addingTimeInterval(7200)
        let expected = Calendar.current.date(byAdding: .month, value: 6, to: pass)!
        #expect(Revisit.defaultDay(after: pass) == WorkDay(containing: expected))
    }

    @Test func aRevisitIsAFactOnItsDayAndNotBefore() throws {
        let store = try makeStore()
        let bolt = try deal("Bolt Pay", stage: "Rejected")
        try store.setRevisit(of: bolt, on: due, reason: "no revenue")
        #expect(try needs(store, on: day(179)).isEmpty, "the day before: nothing")
        let onTheDay = try needs(store, on: day(180))
        #expect(onTheDay.map(\.reason) == [.revisit])
        #expect(onTheDay[0].item.quote == "Revisit Bolt Pay: passed for no revenue; anything new?")
        #expect(onTheDay[0].item.source == .typed && onTheDay[0].item.run == nil)
        #expect(try needs(store, on: day(200)).count == 1, "a missed day stays until done")
    }

    @Test func aRevisitWithNoReasonSaysSoPlainly() throws {
        let store = try makeStore()
        let bolt = try deal("Bolt Pay", stage: "Rejected")
        try store.setRevisit(of: bolt, on: due, reason: "  ")
        #expect(try store.queries.revisits(of: bolt.id).first?.quote == "Revisit Bolt Pay: passed; anything new?")
    }

    @Test func doneClosesItAndANewDateReplacesTheOldOne() throws {
        let store = try makeStore()
        let bolt = try deal("Bolt Pay", stage: "Rejected")
        let first = try store.setRevisit(of: bolt, on: due, reason: "no revenue")
        let second = try store.setRevisit(of: bolt, on: due.adding(days: 30), reason: "no revenue")
        #expect(try store.queries.openRevisits().compactMap(\.id) == [second], "one open revisit for a deal")
        #expect(try needs(store, on: day(180)).isEmpty, "the first date no longer stands")
        try store.apply(Revisit.lifecycle.closing(try store.queries.openRevisits()))
        #expect(try needs(store, on: day(220)).isEmpty)
        #expect(try store.queries.revisits(of: bolt.id).compactMap(\.id) == [first, second])
    }

    @Test func aDealThatCameBackFromRejectedLosesItsRevisit() throws {
        let store = try makeStore()
        let bolt = try deal("Bolt Pay", stage: "Rejected")
        try store.setRevisit(of: bolt, on: due, reason: "no revenue")
        try store.dropRevisits(of: bolt.id)
        #expect(try needs(store, on: day(181)).isEmpty)
    }

    @Test func aHiddenRevisitIsNotListed() throws {
        let store = try makeStore()
        let id = try store.setRevisit(of: try deal("Bolt Pay", stage: "Rejected"), on: due, reason: nil)
        try store.apply(.notRelevant, to: [id])
        #expect(try needs(store, on: day(181)).isEmpty)
    }

    private func signal(_ store: Store, polarity: String, trusted: String, company: String = "d1", on date: Date = t0)
        throws
    {
        try store.insertSignal(
            [
                "company": "Bolt Pay", "company_id": company, "event": "layoff", "polarity": polarity,
                "trusted": trusted,
            ],
            at: date)
    }

    @Test func badNewsFromATrustedFeedNeedsYouAndEverythingElseDoesNot() throws {
        let store = try makeStore()
        try signal(store, polarity: "negative", trusted: "yes")
        try signal(store, polarity: "negative", trusted: "no")
        try signal(store, polarity: "positive", trusted: "yes")
        try signal(store, polarity: "neutral", trusted: "yes")
        let found = try needs(store, on: t0)
        #expect(found.count == 1 && found[0].reason == .news)
        #expect(found[0].item.fields["polarity"] == "negative" && found[0].item.fields["trusted"] == "yes")
    }

    @Test func badNewsLeavesTodayWhenDoneOrHiddenAndStaysOnItsPage() throws {
        let store = try makeStore()
        try signal(store, polarity: "negative", trusted: "yes")
        try signal(store, polarity: "negative", trusted: "yes")
        let ids = try store.queries.newsSignals().compactMap(\.id)
        try store.apply(.done(outcome: "handled"), to: [ids[0]])
        try store.apply(.notRelevant, to: [ids[1]])
        #expect(try needs(store, on: t0).isEmpty)
        #expect(try store.queries.newsSignals().count == 2, "both stay on the Signals page")
    }

    @Test func aMachinesOwnTaskOwnsItsSignalsButATrialAndOtherTasksDoNot() throws {
        #expect(NewsSignals.owns("vc.news-signals") && NewsSignals.owns("vc.news-signals-a1b2c3d4"))
        #expect(!NewsSignals.owns("vc.news-signals-a1b2c3d4#trial") && !NewsSignals.owns("vc.news-signalsx"))
        #expect(!NewsSignals.owns("vc.signals-a1b2c3d4"))
        let store = try makeStore()
        try store.insertSignal(["company_id": "d1", "polarity": "negative"], at: t0, task: "vc.news-signals-a1b2c3d4")
        try store.insertSignal(["company_id": "d1"], at: t0, task: "vc.news-signals-a1b2c3d4#trial")
        try store.insertSignal(["company_id": "d1"], at: t0, task: "vc.signals-a1b2c3d4")
        #expect(try store.queries.newsSignals(of: "d1").count == 1)
    }

    @Test func theSignalsSinceThePassBelongToTheDealAndEarlierOnesDoNot() throws {
        let store = try makeStore()
        try signal(store, polarity: "negative", trusted: "yes", company: "d1", on: day(-3))
        try signal(store, polarity: "positive", trusted: "yes", company: "d1", on: day(40))
        try signal(store, polarity: "positive", trusted: "yes", company: "d2", on: day(41))
        let since = try store.queries.newsSignals(of: "d1", since: WorkDay(containing: t0))
        #expect(since.map { $0["polarity"] } == ["positive"])
        #expect(try store.queries.newsSignals(of: "d1").count == 2)
    }
}

extension Store {
    /// A news signal as a reading would have saved it, for tests that need only its fields.
    func insertSignal(_ fields: [String: String], at date: Date, task: String = NewsSignals.task) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO run(task, model, prompt, input_bytes, input_sha, started_at, ended_at, outcome)
                    VALUES ('t', 'm', 'p', 0, 's', ?, ?, 'done')
                    """, arguments: [date.stored, date.stored])
            try db.execute(
                sql: """
                    INSERT INTO item(task, run_id, day, scope, source, cite_first, cite_last, start_at, end_at, fields,
                        quote, created_at) VALUES (?,?,?,?,?,1,1,?,?,?,?,?)
                    """,
                arguments: [
                    task, db.lastInsertedRowID, WorkDay(containing: date).description, "",
                    SourceKind.web.rawValue, date.stored, date.stored, try Coding.json(fields), "a quote", date.stored,
                ])
        }
    }
}

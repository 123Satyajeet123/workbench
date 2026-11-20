import Foundation
import Testing

@testable import WorkbenchCore

private let today = WorkDay(containing: t0)

private func fact(
    _ id: Int64, person: String = "Asha", project: String = "Deck", kind: String = "plan", asks: String = "team",
    eta: String = "", day: WorkDay = today, state: Mark = .proposed
) -> Item {
    Item(
        id: id, task: "team.ledger", day: day, scope: "work", source: .whatsapp, citeFirst: id, citeLast: id,
        start: day.start.addingTimeInterval(Double(id)), end: day.start.addingTimeInterval(Double(id)),
        fields: ["person": person, "project": project, "kind": kind, "text": "fact \(id)", "asks": asks, "eta": eta],
        quote: "q\(id)", state: state, run: RunID(1))
}

private func finding(_ id: Int64, severity: String) -> Item {
    Item(
        id: id, task: "work.derailment", day: today, scope: "work", source: .whatsapp, citeFirst: 0, citeLast: 0,
        start: today.start, end: today.start, fields: ["severity": severity, "kind": "overdue", "next": "n"],
        quote: "q\(id)", run: RunID(1))
}

private func hidden(_ item: Item) -> Item {
    var item = item
    item.hiding = .hidden
    return item
}

private func closed(_ item: Item) -> Item {
    var item = item
    item.closed = Item.Closed(outcome: "kept", quote: nil, at: t0)
    return item
}

@Suite struct NeedsTests {
    private func pick(facts: [Item] = [], findings: [Item] = []) -> [Need] {
        Needs.pick(facts: facts, findings: findings, today: today, now: t0)
    }

    @Test func factsThatAskTheFounderAndFactsDueTodayNeedYouAndOtherFactsDoNot() {
        let needs = pick(facts: [
            fact(1, asks: "founder"), fact(2, eta: today.description), fact(3, eta: today.adding(days: 1).description),
            fact(4), fact(5, kind: "question", asks: "founder"),
        ])
        #expect(needs.map(\.id) == [1, 5, 2])
    }

    @Test func aFactDueBeforeTodayIsOverdueAndStillNeedsYou() {
        let overdue = today.adding(days: -2)
        let needs = pick(facts: [fact(1, eta: today.description), fact(2, eta: overdue.description)])
        #expect(needs.map(\.reason) == [.due(overdue), .due(today)])
    }

    @Test func anEtaThatIsNotADateIsNeverDue() {
        #expect(pick(facts: [fact(1, eta: "kal tak"), fact(2, eta: "2026-13-40")]).isEmpty)
    }

    @Test func findingsOfSeverityActComeFirstAndWatchLastAndInfoIsLeftOut() {
        let needs = pick(
            facts: [fact(1, asks: "founder")],
            findings: [finding(10, severity: "watch"), finding(11, severity: "info"), finding(12, severity: "act")])
        #expect(needs.map(\.id) == [12, 1, 10])
        #expect(needs.map(\.reason) == [.act, .asks, .watch])
    }

    @Test func aHiddenSnoozedClosedOrWrongItemIsLeftOut() {
        var snoozed = fact(2, asks: "founder")
        snoozed.hiding = .snoozed(until: t0.addingTimeInterval(60))
        let needs = pick(
            facts: [
                hidden(fact(1, asks: "founder")), snoozed, closed(fact(3, asks: "founder")),
                fact(4, asks: "founder", state: .rejected), fact(5, asks: "founder"),
            ],
            findings: [hidden(finding(10, severity: "act")), closed(finding(11, severity: "act"))])
        #expect(needs.map(\.id) == [5])
    }

    @Test func aSnoozedFactComesBackWhenItsDateIsReached() {
        var snoozed = fact(1, asks: "founder")
        snoozed.hiding = .snoozed(until: t0.addingTimeInterval(60))
        let later = Needs.pick(facts: [snoozed], findings: [], today: today, now: t0.addingTimeInterval(60))
        #expect(later.map(\.id) == [1])
    }
}

@Suite struct FactGroupsTests {
    private let lifecycle = HelperSpec.team.lifecycle

    private func groups(_ facts: [Item], by field: String = "person") -> [FactGroup] {
        FactGroups.make(facts, by: field, lifecycle: lifecycle, now: t0)
    }

    @Test func factsAreGroupedByTheFieldWithOpenOnesFirstAndTheRestBelow() {
        let result = groups([
            fact(1, person: "Raj", kind: "done"), fact(2, person: "Asha", kind: "done"),
            fact(3, person: "Asha", kind: "blocker"), fact(4, person: "Asha", kind: "plan"),
        ])
        #expect(result.map(\.name) == ["Asha", "Raj"])
        #expect(result[0].open.map(\.id) == [4, 3] && result[0].rest.map(\.id) == [2])
        #expect(result[1].open.isEmpty && result[1].rest.map(\.id) == [1])
    }

    @Test func aGroupWithOpenFactsComesBeforeOneWithNone() {
        let result = groups([fact(1, person: "Asha", kind: "done"), fact(2, person: "Zed", kind: "plan")])
        #expect(result.map(\.name) == ["Zed", "Asha"])
    }

    @Test func theSoonestDueFactComesFirstAmongTheOpenOnes() {
        let result = groups([
            fact(1, eta: today.adding(days: 3).description), fact(2), fact(3, eta: today.adding(days: 1).description),
        ])
        #expect(result[0].open.map(\.id) == [3, 1, 2])
    }

    @Test func aClosedFactIsNotOpenAndAHiddenOrWrongFactIsInNoGroup() {
        let result = groups([closed(fact(1)), hidden(fact(2)), fact(3, state: .rejected), fact(4, kind: "status")])
        #expect(result.count == 1)
        #expect(result[0].open.isEmpty && Set(result[0].rest.map(\.id)) == [1, 4])
    }

    @Test func aFactWithNoValueInTheFieldBelongsToNoGroup() {
        #expect(groups([fact(1, project: "")], by: "project").isEmpty)
        #expect(groups([fact(1, project: "Deck")], by: "project").map(\.name) == ["Deck"])
    }

    @Test func withoutSummariesEveryListedFactOfAnUnsummarizedPersonIsKeptAndNoOtherPersonIs() {
        let facts = [fact(1, person: "Asha"), fact(2, person: "Raj", kind: "done"), fact(3, person: "Raj")]
        let result = FactGroups.unsummarized(
            facts, by: "person", lifecycle: lifecycle, summarized: ["Asha"], now: t0)
        #expect(result.map(\.name) == ["Raj"])
        #expect(result[0].open.map(\.id) == [3] && result[0].rest.map(\.id) == [2])
        let none = FactGroups.unsummarized(facts, by: "person", lifecycle: lifecycle, summarized: [], now: t0)
        #expect(none.map(\.name) == ["Asha", "Raj"])
    }

    @Test func aFactWithNoPersonStillShowsInAGroupWithNoName() {
        let facts = [fact(1, person: ""), fact(2, person: "Asha"), hidden(fact(3, person: ""))]
        let result = FactGroups.unsummarized(facts, by: "person", lifecycle: lifecycle, summarized: [], now: t0)
        #expect(result.map(\.name) == ["Asha", ""] && result[1].rest.map(\.id) == [1])
        let allSummarized = FactGroups.unsummarized(
            facts, by: "person", lifecycle: lifecycle, summarized: ["Asha"], now: t0)
        #expect(allSummarized.map(\.name) == [""])
    }

    @Test func aMachineWithNoLifecycleHasNoOpenFacts() {
        let result = FactGroups.make([fact(1)], by: "person", lifecycle: nil, now: t0)
        #expect(result.first?.open.isEmpty == true && result.first?.rest.count == 1)
    }
}

@Suite struct ClosingTests {
    private let lifecycle = HelperSpec.Lifecycle(
        field: "kind", open: ["plan", "blocker"], outcomes: ["kept", "resolved"])

    @Test func eachOpenFactGetsItsOwnOutcomeAndOthersAreLeftAlone() {
        let plan = lifecycle.closing([
            fact(1, kind: "plan"), fact(2, kind: "blocker"), fact(3, kind: "blocker"), fact(4, kind: "done"),
            closed(fact(5, kind: "plan")),
        ])
        #expect(plan == [.done(outcome: "kept"): [1], .done(outcome: "resolved"): [2, 3]])
    }

    @Test func nothingOpenMeansNothingToClose() {
        #expect(lifecycle.closing([fact(1, kind: "status"), closed(fact(2))]).isEmpty)
    }

    @Test func aSpecNamesItsPersonAndProjectFieldsByKind() {
        #expect(HelperSpec.team.memberField == "person" && HelperSpec.team.labelField == "project")
        #expect(HelperSpec.timeline.memberField == nil && HelperSpec.timeline.labelField == nil)
    }
}

@Suite struct SummaryLinesTests {
    @Test func aLineLeavesWhenEveryFactItCitesIsGoneAndStaysWhileOneRemains() {
        let line = Summary.Line(text: "Asha shipped.", cites: [1, 2])
        #expect(line.isShown(among: [2, 9]))
        #expect(!line.isShown(among: [9]))
        #expect(!line.isShown(among: []))
    }

    @Test func aScopeNamesItsSubjectWithoutTheField() {
        let summary = Summary(scope: "person: Asha", short: nil, details: [], run: RunID(1))
        #expect(summary.subject == "Asha")
        #expect(Summary(scope: "project: Deck: v2", short: nil, details: [], run: RunID(1)).subject == "Deck: v2")
    }
}

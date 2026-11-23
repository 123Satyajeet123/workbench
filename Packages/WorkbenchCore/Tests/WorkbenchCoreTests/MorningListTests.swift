import Foundation
import Testing

@testable import WorkbenchCore

private let today = WorkDay(containing: t0)
private let yesterday = today.adding(days: -1)
private let tomorrow = today.adding(days: 1)

/// An open commitment of the fact machine. `person` is its owner and `asks` says whether it waits on the founder.
private func commitment(
    _ id: Int64, person: String = "Asha", asks: String = "team", due: WorkDay? = nil, asker: String? = nil
) -> Item {
    var fields = ["person": person, "kind": "commitment", "text": "fact \(id)", "asks": asks]
    if let asker { fields["asker"] = asker }
    return Item(
        id: id, task: "team.ledger", day: today, scope: "work", source: .whatsapp, citeFirst: id, citeLast: id,
        start: today.start, end: today.start, fields: fields, quote: "q\(id)", run: RunID(1),
        due: due.map { Due.stated(on: $0) })
}

private func finding(_ id: Int64, severity: String) -> Item {
    Item(
        id: id, task: "work.derailment", day: today, scope: "work", source: .whatsapp, citeFirst: 0, citeLast: 0,
        start: today.start, end: today.start, fields: ["severity": severity], quote: "q\(id)", run: RunID(1))
}

private func with(_ item: Item, _ change: (inout Item) -> Void) -> Item {
    var item = item
    change(&item)
    return item
}

private func sections(
    _ facts: [Item], findings: [Item] = [], fired: Set<Int64> = [], me: String = "Kabir", asker: String? = nil,
    now: Date = t0
) -> [MorningSection] {
    var input = MorningInput(facts: facts, me: me)
    input.findings = findings
    input.firedTimers = fired
    input.ownerField = { _ in "person" }
    input.askerField = { _ in asker }
    return MorningList.pick(input, now: now)
}

/// The lines of the list for tests of other features that end on it, in section order, for a founder named "Kabir".
func pickedNeeds(
    facts: [Item] = [], findings: [Item] = [], revisits: [Item] = [], news: [Item] = [], now: Date
) -> [Need] {
    var input = MorningInput(facts: facts, me: "Kabir")
    input.findings = findings
    input.revisits = revisits
    input.news = news
    return MorningList.pick(input, now: now).flatMap(\.lines)
}

private func ids(_ sections: [MorningSection], _ kind: MorningSection.Kind) -> [Int64] {
    sections.first { $0.kind == kind }?.lines.compactMap(\.id) ?? []
}

@Suite struct MorningListTests {
    // MARK: What I owe

    @Test func aCommitmentTheFounderOwnsIsOwedAndAnotherPersonsIsWaitedOn() {
        let result = sections([commitment(1, person: "Kabir"), commitment(2, person: "Asha")])
        #expect(ids(result, .owe) == [1])
        #expect(ids(result, .waitingOn) == [2])
    }

    @Test func aFactThatAsksTheFounderIsOwedWhoeverItNamesAndOneThatDoesNotIsNot() {
        let result = sections([commitment(1, person: "Asha", asks: "founder"), commitment(2, person: "Asha")])
        #expect(ids(result, .owe) == [1] && ids(result, .waitingOn) == [2])
        #expect(result.first { $0.kind == .owe }?.needs.map(\.reason) == [.asks])
    }

    @Test func aFounderWhoseNameIsNotSetOwnsNothingNotEvenAFactWithNoOwner() {
        let result = sections(
            [commitment(1, person: ""), commitment(2, person: "Asha", asker: "")], me: "", asker: "asker")
        #expect(ids(result, .owe).isEmpty && ids(result, .owedToMe).isEmpty)
    }

    @Test func theOwnerNameIsMatchedWithoutRegardToCaseOrEdgeSpaces() {
        #expect(ids(sections([commitment(1, person: " kabir ")]), .owe) == [1])
    }

    // MARK: Owed to me

    @Test func aFactAnotherPersonOwesAndTheFounderAskedForIsOwedToTheFounder() {
        let result = sections([commitment(1, person: "Asha", asker: "Kabir")], asker: "asker")
        #expect(ids(result, .owedToMe) == [1] && ids(result, .waitingOn).isEmpty)
    }

    @Test func aFactAskedByAnotherPersonOrByNoOneNamedIsNotOwedToTheFounder() {
        let result = sections(
            [commitment(1, person: "Asha", asker: "Raj"), commitment(2, person: "Asha")], asker: "asker")
        #expect(ids(result, .owedToMe).isEmpty && ids(result, .waitingOn) == [1, 2])
    }

    @Test func aMachineWithNoAskerFieldHasNothingOwedToTheFounder() {
        let result = sections([commitment(1, person: "Asha", asker: "Kabir")])
        #expect(ids(result, .owedToMe).isEmpty && ids(result, .waitingOn) == [1])
    }

    // MARK: Slipped

    @Test func aFactWhoseDueTimePassedHasSlippedWhoeverOwnsIt() {
        let result = sections([
            commitment(1, person: "Kabir", due: yesterday), commitment(2, person: "Asha", due: yesterday),
            commitment(3, person: "Kabir", due: tomorrow),
        ])
        #expect(ids(result, .slipped) == [1, 2] && ids(result, .owe) == [3])
        #expect(result.first { $0.kind == .slipped }?.needs.map(\.reason) == [.due(yesterday), .due(yesterday)])
    }

    @Test func aFactDueLaterTodayHasNotSlippedYet() {
        let result = sections([commitment(1, person: "Kabir", due: today)])
        #expect(ids(result, .slipped).isEmpty && ids(result, .owe) == [1])
    }

    @Test func aFactWhoseTimerFiredHasSlippedAndOneWhoseTimerDidNotHasNot() {
        let result = sections([commitment(1, person: "Asha"), commitment(2, person: "Asha")], fired: [1])
        #expect(ids(result, .slipped) == [1] && ids(result, .waitingOn) == [2])
        #expect(result.first { $0.kind == .slipped }?.needs.map(\.reason) == [.timerFired])
    }

    @Test func aFactWithNoDueTimeOrAnUnreadableOneNeverSlips() throws {
        var unreadable = commitment(1, person: "Asha")
        unreadable.fields[Item.dueField] = "kal tak"
        let noTime = with(commitment(2, person: "Asha")) {
            $0.fields[Item.dueField] = try? Coding.json(Due.unresolved(.none, zone: .current))
        }
        #expect(ids(sections([unreadable, noTime, commitment(3)]), .slipped).isEmpty)
    }

    @Test func theSoonestSlippedFactComesFirst() {
        let result = sections([
            commitment(1, due: yesterday), commitment(2, due: yesterday.adding(days: -3)),
        ])
        #expect(ids(result, .slipped) == [2, 1])
    }

    // MARK: To confirm

    @Test func aFactWithAProposalToCloseIsToConfirmAndOneWithoutIsNot() {
        let proposed = with(commitment(1, person: "Kabir")) {
            $0.proposedClose = Item.Closed(outcome: "kept", quote: "done", at: t0)
        }
        let result = sections([proposed, commitment(2, person: "Kabir")])
        #expect(ids(result, .toConfirm) == [1] && ids(result, .owe) == [2])
        #expect(result.first { $0.kind == .toConfirm }?.needs.map(\.reason) == [.proposedClose(outcome: "kept")])
    }

    // MARK: Hand off

    @Test func aFactHandedToAnotherPersonMovesFromOweToWaitingOnThemEvenIfItAskedTheFounder() {
        let handed = with(commitment(1, person: "Kabir", asks: "founder")) { $0.handedTo = "Raj" }
        let result = sections([handed])
        #expect(ids(result, .owe).isEmpty)
        #expect(result.first { $0.kind == .waitingOn }?.owners.map(\.owner) == ["Raj"])
    }

    @Test func aFactHandedBackToTheFounderIsOwedAgain() {
        let back = with(commitment(1, person: "Asha")) { $0.handedTo = "Kabir" }
        #expect(ids(sections([back]), .owe) == [1])
    }

    // MARK: Waiting on whom

    @Test func waitingOnGroupsByOwnerInNameOrderWhateverTheNumberOfFactsEachOwns() {
        let result = sections([
            commitment(1, person: "Zed"), commitment(2, person: "Zed"), commitment(3, person: "Zed"),
            commitment(4, person: "Asha"), commitment(5, person: "mia"),
        ])
        let waiting = result.first { $0.kind == .waitingOn }
        #expect(waiting?.owners.map(\.owner) == ["Asha", "mia", "Zed"], "the list ranks people")
        #expect(waiting?.owners.map { $0.needs.count } == [1, 1, 3])
    }

    @Test func aGroupCarriesNoCountOfItsOwn() {
        let names = Mirror(reflecting: OwnerGroup(owner: "Asha", needs: [])).children.compactMap(\.label)
        #expect(names == ["owner", "needs"])
    }

    @Test func aFactWithNoOwnerNamedIsWaitedOnByNobody() {
        #expect(sections([commitment(1, person: "")]).isEmpty)
    }

    // MARK: What stays out

    @Test func aClosedHiddenWrongOrSnoozedFactIsNotInTheList() {
        let snoozed = with(commitment(4, person: "Kabir")) { $0.hiding = .snoozed(until: t0.addingTimeInterval(60)) }
        let result = sections([
            with(commitment(1, person: "Kabir")) { $0.closed = Item.Closed(outcome: "kept", quote: nil, at: t0) },
            with(commitment(2, person: "Kabir")) { $0.hiding = .hidden },
            with(commitment(3, person: "Kabir")) { $0.state = .rejected }, snoozed, commitment(5, person: "Kabir"),
        ])
        #expect(ids(result, .owe) == [5])
    }

    @Test func aSnoozedFactComesBackWhenItsDayIsReached() {
        let snoozed = with(commitment(1, person: "Kabir")) { $0.hiding = .snoozed(until: t0.addingTimeInterval(60)) }
        #expect(ids(sections([snoozed], now: t0.addingTimeInterval(30)), .owe).isEmpty, "before its day")
        #expect(ids(sections([snoozed], now: t0.addingTimeInterval(60)), .owe) == [1], "on its day")
    }

    @Test func aFactAppearsInOneSectionOnly() {
        let both = with(commitment(1, person: "Kabir", asks: "founder", due: yesterday)) {
            $0.proposedClose = Item.Closed(outcome: "kept", quote: nil, at: t0)
        }
        let result = sections([both], fired: [1])
        #expect(result.map(\.kind) == [.toConfirm])
    }

    // MARK: Findings

    @Test func findingsThatAskForActionComeBeforeThoseToWatchAndInfoIsLeftOut() {
        let result = sections(
            [], findings: [finding(10, severity: "watch"), finding(11, severity: "info"), finding(12, severity: "act")])
        #expect(ids(result, .findings) == [12, 10])
        #expect(result.first?.needs.map(\.reason) == [.act, .watch])
    }

    @Test func aHiddenOrClosedFindingIsLeftOut() {
        let result = sections(
            [],
            findings: [
                with(finding(10, severity: "act")) { $0.hiding = .hidden },
                with(finding(11, severity: "act")) { $0.closed = Item.Closed(outcome: "x", quote: nil, at: t0) },
            ])
        #expect(result.isEmpty)
    }

    // MARK: Order and count

    @Test func sectionsComeInTheOrderToConfirmSlippedOweFindingsOwedWaiting() {
        let proposed = with(commitment(1, person: "Kabir")) {
            $0.proposedClose = Item.Closed(outcome: "kept", quote: nil, at: t0)
        }
        let result = sections(
            [
                commitment(6, person: "Asha"), commitment(5, person: "Asha", asker: "Kabir"),
                commitment(3, person: "Kabir"), commitment(2, person: "Asha", due: yesterday), proposed,
            ], findings: [finding(4, severity: "act")], asker: "asker")
        #expect(result.map(\.kind) == [.toConfirm, .slipped, .owe, .findings, .owedToMe, .waitingOn])
    }

    @Test func theCountOfWhatNeedsTheFounderLeavesOutWhatIsOwedToThemAndWhatIsWaitedOn() {
        let result = sections(
            [
                commitment(1, person: "Kabir"), commitment(2, person: "Asha", due: yesterday),
                commitment(3, person: "Asha", asker: "Kabir"), commitment(4, person: "Raj"),
            ], findings: [finding(5, severity: "watch")], asker: "asker")
        #expect(MorningList.needsCount(result) == 3)
    }

    @Test func aListWithNothingInItHasNoSectionsAndNoCount() {
        #expect(sections([]).isEmpty && MorningList.needsCount([]) == 0)
    }
}

import AppKit
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The fact components: what a fact offers, how each surface acts, and the card.
@Suite(.serialized) struct FactComponentTests {
    // MARK: What a fact offers

    @Test func anAuditPickOffersRightAndWrongOnly() {
        let pick = FactFixture.item(1, askedWith: 0.2)
        #expect(FactAction.offered(for: pick, isOpenFact: true) == [.right, .wrong])
        #expect(FactAction.offered(for: pick, isOpenFact: false) == [.right, .wrong])
    }

    @Test func anOpenFactOffersDoneSnoozeNotRelevantAndWrong() {
        #expect(
            FactAction.offered(for: FactFixture.item(1), isOpenFact: true)
                == [.done, .snooze(days: 1), .notRelevant, .wrong])
    }

    @Test func anyOtherUnmarkedItemOffersRightAndWrong() {
        #expect(FactAction.offered(for: FactFixture.item(1), isOpenFact: false) == [.right, .wrong])
    }

    @Test func aMarkedItemOffersNothing() {
        for state in [Mark.confirmed, .rejected] {
            for pick in [nil, 0.2] {
                for open in [true, false] {
                    let item = FactFixture.item(1, state: state, askedWith: pick)
                    #expect(FactAction.offered(for: item, isOpenFact: open).isEmpty)
                }
            }
        }
    }

    @Test func everyActionHasItsOwnKeyAWordAndAnIcon() {
        let all: [FactAction] = [.right, .done, .snooze(days: 1), .notRelevant, .wrong]
        #expect(all.map(\.key) == ["Y", "D", "S", "X", "N"])
        for action in all {
            #expect(!action.title.isEmpty)
            #expect(NSImage(systemSymbolName: action.symbol, accessibilityDescription: nil) != nil)
            #expect(NSImage(systemSymbolName: action.confirmedSymbol, accessibilityDescription: nil) != nil)
        }
        #expect(FactAction.snoozes.map(\.choiceTitle) == ["1 day", "3 days", "A week"])
    }

    // MARK: The surfaces

    @Test func todayActsThroughItsModelAndUndoRestoresTheFact() async throws {
        let day = try await FactFixture.day()
        let acting = TodayActing(model: day.today, crew: day.crew, now: { FactFixture.now })
        let blocker = try day.plainFacts()[0]
        let id = try #require(blocker.id)
        #expect(acting.offered(for: blocker) == [.done, .snooze(days: 1), .notRelevant, .wrong])
        let undo = try #require(try acting.perform(.done, on: [blocker], surface: .today))
        #expect(try day.fact(id).closed != nil)
        undo()
        #expect(try day.fact(id).closed == nil)
        let snooze = try #require(try acting.perform(.snooze(days: 3), on: [blocker], surface: .today))
        #expect(try day.fact(id).isHidden(at: FactFixture.now))
        snooze()
        #expect(try !day.fact(id).isHidden(at: FactFixture.now))
    }

    @Test func todayDoesNothingForAFactAnotherPageAlreadyClosedAndOffersNoRight() async throws {
        let day = try await FactFixture.day()
        let id = try #require(day.plainFacts()[0].id)
        let other = try #require(day.plainFacts()[1].id)
        let acting = TodayActing(model: day.today, crew: day.crew, now: { FactFixture.now })
        _ = try #require(try acting.perform(.done, on: [try day.fact(id)], surface: .today))
        #expect(try acting.perform(.done, on: [try day.fact(id)], surface: .today) == nil)
        #expect(try acting.perform(.right, on: [try day.fact(other)], surface: .today) == nil)
        #expect(!acting.offered(for: try day.fact(other)).contains(.right))
    }

    @Test func reviewMarksThroughItsQueueAndUndoPutsTheItemBack() async throws {
        let day = try await FactFixture.day()
        let acting = ReviewActing(model: day.review)
        let item = try #require(day.review.items.first)
        let before = day.review.items.count
        #expect(acting.offered(for: item) == [.right, .wrong])
        let undo = try #require(try acting.perform(.wrong, on: [item], surface: .review))
        #expect(day.review.items.count == before - 1 && !day.review.items.contains { $0.id == item.id })
        undo()
        #expect(day.review.items.count == before && day.review.items.contains { $0.id == item.id })
        #expect(try acting.perform(.done, on: [item], surface: .review) == nil)
    }

    @Test func reviewDoesNothingForAFactAnotherPageAlreadyMarked() async throws {
        let day = try await FactFixture.day()
        let acting = ReviewActing(model: day.review)
        let item = try #require(day.review.items.first)
        try day.store.mark(item: #require(item.id), as: .confirmed)
        day.review.refresh()
        #expect(try acting.perform(.right, on: [item], surface: .review) == nil)
    }

    @Test func aMachinePageMarksAndClosesAndUndoRestoresEachState() async throws {
        let day = try await FactFixture.day()
        let acting = MachineActing(helper: day.pip, now: { FactFixture.now })
        let blocker = try day.plainFacts()[0]
        let id = try #require(blocker.id)
        #expect(acting.offered(for: blocker) == [.done, .wrong])
        let reopen = try #require(try acting.perform(.done, on: [blocker], surface: .machinePage))
        #expect(try day.fact(id).closed != nil)
        reopen()
        #expect(try day.fact(id).closed == nil)
        let wrong = try #require(try acting.perform(.wrong, on: [blocker], surface: .machinePage))
        #expect(try day.fact(id).state == .rejected)
        #expect(try acting.offered(for: day.fact(id)).isEmpty)
        wrong()
        #expect(try day.fact(id).state == .proposed)
    }

    @Test func aMachinePageDoesNothingForAMarkedFactOrAnActionItCannotDo() async throws {
        let day = try await FactFixture.day()
        let acting = MachineActing(helper: day.pip, now: { FactFixture.now })
        let fact = try day.plainFacts()[0]
        let id = try #require(fact.id)
        #expect(try acting.perform(.snooze(days: 1), on: [fact], surface: .machinePage) == nil)
        _ = try #require(try acting.perform(.wrong, on: [fact], surface: .machinePage))
        #expect(try acting.perform(.wrong, on: [try day.fact(id)], surface: .machinePage) == nil)
        #expect(try day.fact(id).state == .rejected)
    }

    // MARK: The card

    /// With no width the card takes its ideal size, so a bar that is not reserved changes the width.
    private func size(of card: FactCard, width: CGFloat? = nil, zoom: Double = 1) -> CGSize {
        let host = NSHostingView(
            rootView: card.frame(width: width).environment(\.uiScale, zoom))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private func card(
        _ row: FactRow, isSelected: Bool = false, isHovered: Bool = false, confirming: FactAction? = nil,
        offered: [FactAction] = [.done, .snooze(days: 1), .notRelevant, .wrong]
    ) -> FactCard {
        FactCard(
            row: row, offered: offered, isSelected: isSelected, isHovered: isHovered, confirming: confirming,
            now: FactFixture.now, hover: { _ in }, open: {}, act: { _ in })
    }

    @Test func theCardKeepsItsSizeWhenTheBarShowsAndWhenItConfirms() {
        let row = FactFixture.row(1, due: 0)
        let rest = size(of: card(row))
        #expect(rest.height > 30 && rest.height < 80)
        #expect(size(of: card(row, isSelected: true)) == rest)
        #expect(size(of: card(row, isHovered: true)) == rest)
        #expect(size(of: card(row, confirming: .done)) == rest)
        #expect(size(of: card(row, isSelected: true, offered: [])).height == rest.height)
    }

    @Test func everyKindOfRowHasTheSameHeight() {
        let rest = size(of: card(FactFixture.row(1, due: 0)), width: 640).height
        let long = String(repeating: "A very long title that cannot fit on one line ", count: 8)
        for row in [
            FactFixture.row(2, quote: long), FactFixture.row(3, person: ""), FactFixture.row(4, askedWith: 0.2),
            FactFixture.row(5, due: -2),
        ] {
            #expect(size(of: card(row), width: 640).height == rest, "row \(row.id)")
        }
        for zoom in [1.0, 1.5] {
            let scaled = size(of: card(FactFixture.row(6)), width: 640, zoom: zoom).height
            #expect(size(of: card(FactFixture.row(7, quote: long)), width: 640, zoom: zoom).height == scaled)
        }
    }

    @Test func aFactIsCalledByItsQuoteAndTheTitleStandsInOnlyWithoutOne() {
        let quoted = FactFixture.row(1, title: "Machine title")
        #expect(quoted.headline.words == "login API aaj raat tak" && quoted.headline.isQuote)
        #expect(quoted.headline.plain == "Asha: login API aaj raat tak")
        let bare = FactFixture.row(2, title: "Machine title", quote: "")
        #expect(bare.headline.words == "Machine title" && !bare.headline.isQuote)
        #expect(FactFixture.row(3, title: "Machine title", quote: " \n ").headline.words == "Machine title")
        #expect(FactFixture.row(4, quote: "kal\n  subah   bhejna").headline.words == "kal subah bhejna")
        #expect(FactFixture.row(5, person: "", quote: "ok").headline.plain == "ok")
    }

    @Test func theCardNamesTheChatThenTheProjectThenTheSource() {
        let now = FactFixture.now
        #expect(FactFixture.row(1, chat: "Founders group").said(now: now).hasPrefix("Founders group · "))
        #expect(FactFixture.row(2).said(now: now).hasPrefix("Login · "), "no chat: the project")
        #expect(FactFixture.row(3, project: "").said(now: now).hasPrefix("WhatsApp · "), "no chat, no project")
        #expect(FactFixture.row(4, chat: "asha").said(now: now).hasPrefix("WhatsApp · "), "a chat named for the person")
        #expect(!FactFixture.row(5, chat: "Founders group").said(now: now).contains("Login"))
        #expect(FactFixture.row(6).said(now: now) == "Login · yesterday")
    }

    @Test func theDueDayIsBadWhenLateAndAttentionToday() {
        let today = FactFixture.today
        #expect(FactFixture.row(1, due: 0).due(today: today)?.text == "due today")
        #expect(FactFixture.row(1, due: 0).due(today: today)?.tone == .attention)
        #expect(FactFixture.row(2, due: -1).due(today: today)?.tone == .bad)
        #expect(FactFixture.row(2, due: -1).due(today: today)?.text.hasPrefix("due ") == true)
        #expect(FactFixture.row(3, due: 2).due(today: today)?.tone == .neutral)
        #expect(FactFixture.row(4).due(today: today) == nil)
    }

    @Test func voiceOverReadsTheHeadlineThePlaceAndTheDueDay() {
        let spoken = FactFixture.row(1, due: 0).spoken(now: FactFixture.now)
        #expect(spoken.hasPrefix("Asha: login API aaj raat tak. Login · "))
        #expect(spoken.hasSuffix(". due today"))
        #expect(!FactFixture.row(2, person: "", quote: "").spoken(now: FactFixture.now).hasPrefix("."))
    }

    // MARK: One action in sight

    @Test func anOpenFactShowsDoneAndKeepsTheRestInTheMenu() {
        let split = FactAction.split([.done, .snooze(days: 1), .notRelevant, .wrong])
        #expect(split.primary == [.done] && split.more == [.snooze(days: 1), .notRelevant, .wrong])
        let machine = FactAction.split([.done, .wrong])
        #expect(machine.primary == [.done] && machine.more == [.wrong])
    }

    @Test func aCheckShowsRightAndWrongTogetherAndHasNoMenu() {
        let split = FactAction.split([.right, .wrong])
        #expect(split.primary == [.right, .wrong] && split.more.isEmpty)
    }

    @Test func aFactWithNoQuestionKeepsEveryActionInTheMenu() {
        #expect(FactAction.split([]) == ([], []))
        let lone = FactAction.split([.wrong])
        #expect(lone.primary.isEmpty && lone.more == [.wrong])
        let all: [FactAction] = [.done, .snooze(days: 1), .notRelevant, .wrong, .right]
        let split = FactAction.split(all)
        #expect(Set(split.primary + split.more) == Set(all) && split.primary.count + split.more.count == all.count)
    }

    @Test func theConfirmationIsAFlashOfLightTint() {
        #expect(FactCard.confirmationOpacity < Chip.fillOpacity)
    }

    @Test func toastTextNamesTheActionAndShortensALongTitle() {
        #expect(FactAction.snooze(days: 3).toastText(for: "Pay the vendor") == "Snoozed for 3 days: Pay the vendor")
        #expect(FactAction.right.toastText(for: String(repeating: "a", count: 80)).count < 80)
    }
}

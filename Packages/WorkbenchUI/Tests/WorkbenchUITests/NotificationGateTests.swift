import AppKit
import LocalSources
import SwiftUI
import Testing
import UserNotifications

@testable import WorkbenchUI

private final class RecordingNotifier: Notifier {
    var access = SystemAccess.allowed
    var failure: Error?
    var shown: [FactNotice] = []
    var summaries: [String] = []
    var removed: [Int64] = []

    func authorize() async -> SystemAccess { access }
    func post(title: String, body: String, page: SidebarSelection) async throws {
        if let failure { throw failure }
        summaries.append(title)
    }
    func post(_ notice: FactNotice) async throws {
        if let failure { throw failure }
        shown.append(notice)
    }
    func removeDelivered(itemID: Int64) { removed.append(itemID) }
}

private struct PostFailure: Error {}

private let calendar = Calendar(identifier: .gregorian)

private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func scratchDefaults() -> UserDefaults {
    UserDefaults(suiteName: "notification-tests-\(UUID().uuidString)")!
}

private let notice = FactNotice(itemID: 7, title: "Send Asha the term sheet", source: "Team chat", offer: .open)

@Suite struct NotificationGateTests {
    private let policy = NotificationPolicy()

    private func shows(
        now: Date = at(23, 14), front: Bool = false, sent: Int = 0, policy: NotificationPolicy? = nil, open: Bool = true
    ) -> Bool {
        NotificationGate.shows(
            now: now, windowInFront: front, sentToday: sent, policy: policy ?? self.policy, itemOpen: open,
            calendar: calendar)
    }

    @Test func aFactOnADayWithRoomShows() {
        #expect(shows())
    }

    @Test func nothingShowsWhileTheWindowIsInFront() {
        #expect(!shows(front: true))
        #expect(shows(front: false))
    }

    @Test func nothingShowsOnceTheDailyCapIsReached() {
        #expect(shows(sent: 2))
        #expect(!shows(sent: 3))
        #expect(shows(sent: 4, policy: NotificationPolicy(dailyCap: 5)))
    }

    @Test func nothingShowsInQuietHoursAndTheQuietEndsAtItsEndMinute() {
        #expect(!shows(now: at(23, 23, 30)))
        #expect(!shows(now: at(23, 7, 59)))
        #expect(shows(now: at(23, 8)))
        #expect(shows(now: at(23, 21, 59)))
        #expect(!shows(now: at(23, 22)))
    }

    @Test func quietHoursThatAreOffHoldNothingBack() {
        var off = policy
        off.quiet.isOn = false
        #expect(shows(now: at(23, 23), policy: off))
    }

    @Test func quietHoursInsideOneDayAndEmptyQuietHoursWork() {
        let lunch = QuietHours(isOn: true, start: 12 * 60, end: 14 * 60)
        #expect(lunch.contains(at(23, 13), calendar: calendar))
        #expect(!lunch.contains(at(23, 14), calendar: calendar))
        #expect(!lunch.contains(at(23, 11, 59), calendar: calendar))
        let empty = QuietHours(isOn: true, start: 9 * 60, end: 9 * 60)
        #expect(!empty.contains(at(23, 9), calendar: calendar))
    }

    @Test func nothingShowsForAFactThatIsNoLongerOpen() {
        #expect(!shows(open: false))
        #expect(shows(open: true))
    }

    @Test func theDefaultsAreThreeADayAndQuietFrom22To08() {
        #expect(policy.dailyCap == 3)
        #expect(policy.quiet == QuietHours(isOn: true, start: 1320, end: 480))
    }

    @Test func theChoicesSurviveARestart() {
        let defaults = scratchDefaults()
        #expect(NotificationPolicy.saved(in: defaults) == policy)
        let chosen = NotificationPolicy(dailyCap: 5, quiet: QuietHours(isOn: false, start: 60, end: 120))
        chosen.save(in: defaults)
        #expect(NotificationPolicy.saved(in: defaults) == chosen)
    }
}

@Suite struct DailyCountTests {
    @Test func theCountRestartsWhenTheDayChanges() {
        var count = DailyCount.stored(in: scratchDefaults())
        count.record(at: at(23, 23, 50))
        count.record(at: at(23, 23, 55))
        #expect(count.sent(on: at(23, 23, 59), calendar: calendar) == 2)
        #expect(count.sent(on: at(24, 0, 1), calendar: calendar) == 0)
        count.record(at: at(24, 9), calendar: calendar)
        #expect(count.sent(on: at(24, 10), calendar: calendar) == 1)
    }

    @Test func theCountSurvivesARestart() {
        let defaults = scratchDefaults()
        var count = DailyCount.stored(in: defaults)
        count.record(at: at(23, 9))
        count.store(in: defaults)
        #expect(DailyCount.stored(in: defaults).sent(on: at(23, 10), calendar: calendar) == 1)
    }
}

@Suite struct FactNotificationTests {
    private func notifications(
        _ notifier: Notifier, defaults: UserDefaults = scratchDefaults(), now: Date = at(23, 14),
        front: Bool = false
    ) -> Notifications {
        Notifications(notifier: notifier, defaults: defaults, clock: { now }, windowInFront: { front })
    }

    @Test func aFactShowsOnceTheGateAllowsIt() async throws {
        let notifier = RecordingNotifier()
        #expect(try await notifications(notifier).notify(notice, itemOpen: true))
        #expect(notifier.shown == [notice])
    }

    @Test func theFourthNotificationOfTheDayIsHeldBack() async throws {
        let notifier = RecordingNotifier()
        let center = notifications(notifier)
        for id in 1...4 {
            try await center.notify(
                FactNotice(itemID: Int64(id), title: "A", source: "B", offer: .open), itemOpen: true)
        }
        #expect(notifier.shown.map(\.itemID) == [1, 2, 3])
    }

    @Test func aSummaryAndFactsShareOneDailyCap() async throws {
        let notifier = RecordingNotifier()
        let center = notifications(notifier)
        #expect(try await center.notifySummary(title: "3 things need you today", body: "", page: .mochi))
        for id in 1...3 {
            try await center.notify(
                FactNotice(itemID: Int64(id), title: "A", source: "B", offer: .open), itemOpen: true)
        }
        #expect(notifier.summaries == ["3 things need you today"])
        #expect(notifier.shown.map(\.itemID) == [1, 2], "a summary and facts count against two budgets")
    }

    @Test func aSummaryKeepsQuietHoursAndTheWindowRule() async throws {
        let notifier = RecordingNotifier()
        #expect(try await !notifications(notifier, now: at(23, 23)).notifySummary(title: "S", body: "", page: .mochi))
        #expect(try await !notifications(notifier, front: true).notifySummary(title: "S", body: "", page: .mochi))
        #expect(notifier.summaries.isEmpty)
        #expect(try await notifications(notifier).notifySummary(title: "S", body: "", page: .mochi))
        #expect(notifier.summaries == ["S"])
    }

    @Test func aHeldBackFactDoesNotUseUpTheCap() async throws {
        let notifier = RecordingNotifier()
        let defaults = scratchDefaults()
        try await notifications(notifier, defaults: defaults, front: true).notify(notice, itemOpen: true)
        try await notifications(notifier, defaults: defaults).notify(notice, itemOpen: false)
        #expect(notifier.shown.isEmpty)
        #expect(DailyCount.stored(in: defaults).sent(on: at(23, 14), calendar: calendar) == 0)
    }

    @Test func aFailedPostDoesNotUseUpTheCap() async throws {
        let notifier = RecordingNotifier()
        notifier.failure = PostFailure()
        let defaults = scratchDefaults()
        await #expect(throws: PostFailure.self) {
            try await notifications(notifier, defaults: defaults).notify(notice, itemOpen: true)
        }
        #expect(DailyCount.stored(in: defaults).sent(on: at(23, 14), calendar: calendar) == 0)
    }

    @Test func theCountRestartsAtMidnight() async throws {
        let notifier = RecordingNotifier()
        let defaults = scratchDefaults()
        let late = notifications(notifier, defaults: defaults, now: at(23, 21))
        for _ in 1...3 { try await late.notify(notice, itemOpen: true) }
        #expect(try await late.notify(notice, itemOpen: true) == false)
        let nextDay = notifications(notifier, defaults: defaults, now: at(24, 9))
        #expect(try await nextDay.notify(notice, itemOpen: true))
    }

    @Test func nothingIsPostedWhenMacOSBlocksNotifications() async throws {
        let notifier = RecordingNotifier()
        notifier.access = .blocked
        let center = notifications(notifier)
        #expect(try await center.notify(notice, itemOpen: true) == false)
        #expect(notifier.shown.isEmpty && center.blocked)
    }

    @Test func aHandledFactIsRemovedFromNotificationCentre() {
        let notifier = RecordingNotifier()
        notifications(notifier).clear(itemID: 7)
        #expect(notifier.removed == [7])
    }

    @Test func aNotifierWithoutMarksStillShowsTheTitleAndTheSource() async throws {
        let notifier = FakeNotifier()
        try await notifier.post(notice)
        #expect(notifier.posted.map(\.title) == ["Send Asha the term sheet"])
        #expect(notifier.posted.map(\.body) == ["Team chat"])
    }
}

@Suite struct NotificationContentTests {
    @Test func theTextIsTheFactTitleAndTheSourceName() {
        let content = notice.content
        #expect(content.title == "Send Asha the term sheet")
        #expect(content.body == "Team chat")
        #expect(content.subtitle.isEmpty)
        #expect(content.sound == nil)
        #expect(Set(content.userInfo.keys.compactMap { $0 as? String }) == ["page", "fact"])
    }

    @Test func eachKindOffersItsMarksAndEachMarkHasItsId() {
        #expect(FactNotice.Offer.open.actions.map(\.rawValue) == ["done", "snooze1"])
        #expect(FactNotice.Offer.check.actions.map(\.rawValue) == ["right", "wrong"])
        #expect(Set(FactNotice.Offer.allCases.map(\.category)).count == 2)
        #expect(NotificationAction.allCases.map(\.title) == ["Done", "Snooze 1 day", "Right", "Wrong"])
    }

    @Test func aChosenMarkIsAnAnswerAndAClickOnTheBodyOpensTheFact() {
        let info: [AnyHashable: Any] = ["fact": 7, "page": "workbench://open?page=day"]
        for action in NotificationAction.allCases {
            #expect(
                NotificationReply(actionID: action.rawValue, userInfo: info)
                    == .answer(NotificationAnswer(itemID: 7, action: action)))
        }
        #expect(NotificationReply(actionID: NotificationReply.bodyClick, userInfo: info) == .open(itemID: 7))
    }

    @Test func aDismissOrANotificationAboutNoFactIsNoReply() {
        #expect(NotificationReply(actionID: UNNotificationDismissActionIdentifier, userInfo: ["fact": 7]) == nil)
        #expect(NotificationReply(actionID: "done", userInfo: ["page": "workbench://open?page=day"]) == nil)
    }
}

@Suite struct NotificationRepliesTests {
    private let answer = NotificationReply.answer(NotificationAnswer(itemID: 7, action: .done))

    @Test func aReplyThatArrivesBeforeTheWindowWaitsForTheHandler() {
        let replies = NotificationReplies()
        replies.receive(answer)
        var handled: [NotificationReply] = []
        replies.handler = { handled.append($0) }
        #expect(handled == [answer])
        replies.receive(.open(itemID: 7))
        #expect(handled == [answer, .open(itemID: 7)])
    }

    @Test func aReplyIsHandledOnce() {
        let replies = NotificationReplies()
        replies.receive(answer)
        var count = 0
        replies.handler = { _ in count += 1 }
        replies.handler = { _ in count += 1 }
        #expect(count == 1)
    }
}

@Suite struct NotificationSettingsRenderTests {
    private func folder() -> URL {
        let url = URL(filePath: "/Users/jeet/Projects/worktrace/plans/2026-11-23-ux1/shots/L8")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func png(of view: some View, dark: Bool) throws -> Data {
        let size = CGSize(width: 640, height: 420)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    @Test func theSectionIsDrawnWithQuietHoursOnAndOffInLightAndDark() throws {
        let on = scratchDefaults()
        let off = scratchDefaults()
        NotificationPolicy(quiet: QuietHours(isOn: false, start: 1320, end: 480)).save(in: off)
        for (name, defaults) in [("quiet-on", on), ("quiet-off", off)] {
            for (dark, label) in [(false, "light"), (true, "dark")] {
                let data = try png(
                    of: Form { NotificationPolicySection(defaults: defaults) }.formStyle(.grouped), dark: dark)
                try data.write(to: folder().appending(path: "settings-notifications-\(name)-\(label).png"))
                #expect(data.count > 10_000)
            }
        }
    }
}

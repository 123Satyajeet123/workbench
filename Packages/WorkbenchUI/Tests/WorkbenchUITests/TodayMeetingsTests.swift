import CaptureService
import Foundation
import LocalSources
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A calendar of fixed events that counts every ask.
final class FakeCalendar: CalendarEvents, @unchecked Sendable {
    var access = CalendarAccess.allowed
    var events: [Meeting]
    private(set) var accessAsks = 0
    private(set) var reads: [[String]] = []

    init(_ events: [Meeting] = []) { self.events = events }

    func requestAccess() async -> CalendarAccess {
        accessAsks += 1
        return access
    }

    func calendars() -> [CalendarInfo] {
        [CalendarInfo(id: "work", title: "Work"), CalendarInfo(id: "home", title: "Home")]
    }

    func meetings(during interval: DateInterval, in calendarIDs: [String]) -> [Meeting] {
        reads.append(calendarIDs)
        return events.filter { calendarIDs.contains($0.calendar) }
    }
}

/// Today with meetings over a scratch store holding the sample day (Asha, Meera and Raj), the Meetings section, and
/// the way a deal is found.
@MainActor
@Suite struct TodayMeetingsTests {
    private let me = Meeting.Attendee(name: "Kabir", email: "kabir@fund.vc", isMe: true)

    static func meeting(
        _ title: String, calendar: String = "work", hour: Int = 10, guests: [(String, String)] = []
    ) -> Meeting {
        let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
        return Meeting(
            id: title, calendar: calendar, title: title, start: start, end: start.addingTimeInterval(1800),
            attendees: [Meeting.Attendee(name: "Kabir", email: "kabir@fund.vc", isMe: true)]
                + guests.map { Meeting.Attendee(name: $0.0, email: $0.1) },
            notesLength: 40)
    }

    private struct Day {
        let store: Store
        let model: TodayModel
        let calendar: FakeCalendar
        let defaults: UserDefaults
    }

    private func day(
        _ events: [Meeting], consent: CapturePolicy? = CapturePolicy(switches: [.calendar: true]),
        deals: @escaping () -> [WorkObject] = { [] }
    ) async throws -> Day {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        try await TodaySample.populate(store: store, crew: crew)
        var policy = try store.queries.policy()
        policy.switches[.calendar] = consent?.isEnabled(.calendar) ?? false
        policy.allowList[.calendar] = consent?.allowList[.calendar]
        try store.savePolicy(policy)
        let calendar = FakeCalendar(events)
        let defaults = UserDefaults(suiteName: "wb-meetings-\(UUID().uuidString)")!
        let model = TodayModel(store: store, crew: crew, calendar: calendar, deals: deals, defaults: defaults)
        await model.refreshMeetings()
        return Day(store: store, model: model, calendar: calendar, defaults: defaults)
    }

    @Test func withTheConsentOffNothingIsReadAndTheOfferShows() async throws {
        let off = try await day([Self.meeting("Sync")], consent: nil)
        #expect(off.calendar.accessAsks == 0 && off.calendar.reads.isEmpty)
        #expect(off.model.meetingCards.isEmpty && off.model.meetings.offersMeetings)
    }

    @Test func refusedAccessGivesOneLineAndNoMeetings() async throws {
        let store = try scratchStore()
        let calendar = FakeCalendar([Self.meeting("Sync")])
        calendar.access = .blocked
        try store.savePolicy(CapturePolicy(switches: [.calendar: true]))
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Kabir" }, notifier: FakeNotifier())
        let model = TodayModel(store: store, crew: crew, calendar: calendar)
        await model.refreshMeetings()
        #expect(model.meetings.refusal == "macOS has not given Workbench access to your calendar.")
        #expect(model.meetingCards.isEmpty && calendar.reads.isEmpty)
    }

    @Test func onlyTheChosenCalendarsShow() async throws {
        let events = [Self.meeting("Sync"), Self.meeting("Dentist", calendar: "home", hour: 11)]
        let chosen = try await day(
            events, consent: CapturePolicy(switches: [.calendar: true], allowList: [.calendar: ["home"]]))
        #expect(chosen.model.meetingCards.map(\.meeting.title) == ["Dentist"])
        #expect(chosen.calendar.reads == [["home"]])
    }

    @Test func aGuestNamedLikeAPersonGetsThatPersonsOpenFactsAndSummaryLine() async throws {
        let found = try await day([Self.meeting("Catch up", guests: [("Asha", "asha@team.dev")])])
        let prep = try #require(found.model.meetingCards.first?.preps.first)
        #expect(prep.subject == .person("Asha"))
        #expect(prep.line?.hasPrefix("Shipped OTA") == true)
        #expect(!prep.facts.isEmpty && prep.facts.allSatisfy { $0.closed == nil && !$0.quote.isEmpty })
    }

    @Test func aGuestFromADealsCompanyGetsTheDealsActionsAndQuotes() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        fixture.deals.requireAction(deal, what: "Get the cap table", due: WorkDay(containing: .now).adding(days: 3))
        let today = TodayModel(
            store: fixture.store, crew: fixture.crew,
            calendar: FakeCalendar([Self.meeting("Pitch", guests: [("Priya", "priya@acme.com")])]),
            deals: { fixture.deals.deals }, defaults: UserDefaults(suiteName: "wb-\(UUID().uuidString)")!)
        try fixture.store.savePolicy(CapturePolicy(switches: [.calendar: true]))
        await today.refreshMeetings()
        let prep = try #require(today.meetingCards.first?.preps.first)
        #expect(prep.subject == .deal(deal.id) && prep.name == "Acme")
        #expect(prep.facts.map { $0["text"] } == ["Get the cap table"])
        #expect(prep.quotes.map(\.text) == ["Acme is raising"] && prep.quotes[0].source.hasPrefix("a page"))
    }

    @Test func aDealActionTheFounderSnoozedStaysOffTheMeetingCard() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        let due = WorkDay(containing: .now).adding(days: 3)
        fixture.deals.requireAction(deal, what: "Get the cap table", due: due)
        let snoozed = try #require(try fixture.store.queries.openDealActions().first?.id)
        try fixture.store.apply(.snooze(until: due), to: [snoozed], surface: .today)
        let today = TodayModel(
            store: fixture.store, crew: fixture.crew,
            calendar: FakeCalendar([Self.meeting("Pitch", guests: [("Priya", "priya@acme.com")])]),
            deals: { fixture.deals.deals }, defaults: UserDefaults(suiteName: "wb-\(UUID().uuidString)")!)
        try fixture.store.savePolicy(CapturePolicy(switches: [.calendar: true]))
        await today.refreshMeetings()
        let prep = try #require(today.meetingCards.first?.preps.first)
        #expect(prep.subject == .deal(deal.id) && prep.facts.isEmpty)
    }

    @Test func aMeetingThatMatchesNothingShowsWithNoCard() async throws {
        let found = try await day([Self.meeting("Dentist", guests: [("Dr Rao", "rao@clinic.in")])])
        #expect(found.model.meetingCards.map(\.meeting.title) == ["Dentist"])
        #expect(found.model.meetingCards[0].preps.isEmpty)
    }

    @Test func switchingTheConsentOffDropsTheMeetings() async throws {
        let found = try await day([Self.meeting("Sync")])
        #expect(found.model.meetingCards.count == 1)
        var policy = try found.store.queries.policy()
        policy.switches[.calendar] = false
        try found.store.savePolicy(policy)
        await found.model.refreshMeetings()
        #expect(found.model.meetingCards.isEmpty && found.model.meetings.meetings.isEmpty)
    }

    @Test func decliningTheOfferIsRememberedAndTheOfferStopsWhenTheConsentIsOn() async throws {
        let off = try await day([], consent: nil)
        off.model.meetings.declineOffer()
        #expect(!off.model.meetings.offersMeetings && off.defaults.bool(forKey: MeetingsModel.offerDeclinedKey))
        let on = try await day([])
        #expect(!on.model.meetings.offersMeetings)
    }

    @Test func aTodayWithNoCalendarNeverOffersAndNeverReads() async throws {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "" }, notifier: FakeNotifier())
        let model = TodayModel(store: store, crew: crew)
        await model.refreshMeetings()
        #expect(!model.meetings.offersMeetings && model.meetingCards.isEmpty)
    }

    @Test func choosingCalendarsInSettingsWritesTheAllowListAndChoosingAllClearsIt() throws {
        let settings = try captureSettings()
        let all = FakeCalendar().calendars()
        settings.toggle(try #require(settings.calendarChoices(among: all).first { $0.id == "home" }), among: all)
        #expect(settings.calendarChoices(among: all).map(\.isRead) == [true, false])
        settings.toggle(try #require(settings.calendarChoices(among: all).first { $0.id == "home" }), among: all)
        #expect(settings.calendarChoices(among: all).map(\.isRead) == [true, true])
    }
}

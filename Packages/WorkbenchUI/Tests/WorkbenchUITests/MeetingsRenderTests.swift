import AppKit
import CaptureService
import Foundation
import LocalSources
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// Today with meetings drawn through an NSHostingView to a PNG. The folder comes from `TODAY_PREVIEW_DIR`, else the
/// temporary folder.
@MainActor
@Suite struct MeetingsRenderTests {
    private func folder() -> URL {
        ProcessInfo.processInfo.environment["TODAY_PREVIEW_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
    }

    private func snapshot(of model: TodayModel, capture: CaptureSettings, to name: String) throws -> Int {
        let frame = TodayFrame(model: model).environment(capture).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: frame)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: folder(), withIntermediateDirectories: true)
        try data.write(to: folder().appending(path: name))
        return data.count
    }

    private func today(calendar: FakeCalendar, consent: Bool, fixture: DealFixture) async throws -> TodayModel {
        try await TodaySample.populate(store: fixture.store, crew: fixture.crew)
        try fixture.store.savePolicy(
            CapturePolicy(
                switches: [.whatsapp: true, .calendar: consent], allowList: [.whatsapp: [TodaySample.defaultScope]]))
        let model = TodayModel(
            store: fixture.store, crew: fixture.crew, calendar: calendar, deals: { fixture.deals.deals },
            defaults: UserDefaults(suiteName: "wb-render-\(UUID().uuidString)")!)
        await model.refreshMeetings()
        return model
    }

    @Test func todayShowsMeetingsAboveTeamWithPrepCards() async throws {
        let fixture = try DealFixture()
        let deal = try await fixture.deal("Acme", reading: VCFixture.hot)
        fixture.deals.requireAction(deal, what: "Get the cap table", due: WorkDay(containing: .now).adding(days: 3))
        let calendar = FakeCalendar([
            TodayMeetingsTests.meeting("Pitch: Acme", hour: 10, guests: [("Priya Nair", "priya@acme.com")]),
            TodayMeetingsTests.meeting(
                "Catch up", hour: 12, guests: [("Asha", "asha@team.dev"), ("Raj", "raj@team.dev")]),
            TodayMeetingsTests.meeting("Dentist", hour: 17, guests: [("Dr Rao", "rao@clinic.in")]),
        ])
        let model = try await today(calendar: calendar, consent: true, fixture: fixture)
        #expect(model.meetingCards.map { $0.preps.count } == [1, 2, 0])
        let size = try snapshot(of: model, capture: try captureSettings(over: fixture.store), to: "today-meetings.png")
        #expect(size > 20_000)
    }

    @Test func todayOffersMeetingsOnceWhenTheCalendarIsOff() async throws {
        let fixture = try DealFixture()
        let model = try await today(calendar: FakeCalendar(), consent: false, fixture: fixture)
        #expect(model.meetings.offersMeetings)
        #expect(
            try snapshot(of: model, capture: try captureSettings(over: fixture.store), to: "today-offer.png") > 5_000)
    }

    @Test func todayShowsOneLineWhenMacOSRefusesTheCalendar() async throws {
        let fixture = try DealFixture()
        let calendar = FakeCalendar([TodayMeetingsTests.meeting("Sync")])
        calendar.access = .blocked
        let model = try await today(calendar: calendar, consent: true, fixture: fixture)
        #expect(model.meetings.refusal != nil)
        #expect(
            try snapshot(of: model, capture: try captureSettings(over: fixture.store), to: "today-denied.png") > 5_000)
    }
}

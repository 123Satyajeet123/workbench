import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

struct PopupCardsTests {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func meeting(_ id: String, at minutes: Double, link: Bool = true) -> Meeting {
        Meeting(
            id: id, calendar: "work", title: id, start: start.addingTimeInterval(minutes * 60),
            end: start.addingTimeInterval((minutes + 30) * 60),
            joinURL: link ? URL(string: "https://meet.google.com/abc-defg-hij") : nil)
    }

    @Test func aMeetingShowsFromAMinuteBeforeUntilFiveMinutesInAndOnlyWithALink() {
        let meetings = [meeting("Standup", at: 0), meeting("No link", at: 0, link: false), meeting("Later", at: 30)]
        func shown(_ minutes: Double) -> [String] {
            PopupCards.make(
                recording: nil, offer: nil, meetings: meetings, dismissed: [],
                now: start.addingTimeInterval(minutes * 60)
            ).map(\.id)
        }
        #expect(shown(-1.5) == [])
        #expect(shown(-1) == ["meeting:Standup"])
        #expect(shown(4.9) == ["meeting:Standup"])
        #expect(shown(5) == [])
        #expect(shown(29.5) == ["meeting:Later"])
    }

    @Test func aDismissedMeetingStaysAwayAndACallComesFirst() {
        let standup = meeting("Standup", at: 0)
        let cards = PopupCards.make(
            recording: nil, offer: "Zoom", meetings: [standup, meeting("Sync", at: 1)], dismissed: ["meeting:Standup"],
            now: start)
        #expect(cards.map(\.id) == ["offer", "meeting:Sync"])
        #expect(PopupCards.when(standup, at: start.addingTimeInterval(-60)) == "Starts in 1 min")
        #expect(PopupCards.when(standup, at: start.addingTimeInterval(180)) == "Started 3 min ago")
    }

    @Test func whileRecordingTheRecordingReplacesTheOffer() throws {
        let store = try scratchStore()
        let grant = try #require(
            CapturePolicy(switches: [.call: true])
                .authorize(CaptureRequest(kind: .call, label: "us.zoom.xos", liveSession: true), at: Date()).grant)
        let call = try store.startRecording(
            app: "zoom.us", bundleID: "us.zoom.xos", source: CallSource(service: "Zoom", title: "Acme intro"),
            grant: grant)
        let cards = PopupCards.make(recording: call, offer: "Zoom", meetings: [], dismissed: [], now: start)
        #expect(cards == [.recording(label: "Zoom · Acme intro", since: call.startedAt)])
    }

    @Test func thePopUpIsChosenInSettingsAndTheNotchIsTheDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "popup-\(UUID().uuidString)"))
        #expect(AlertStyle.current(in: defaults) == .notch)
        defaults.set(AlertStyle.popup.rawValue, forKey: IslandKey.style)
        #expect(AlertStyle.current(in: defaults) == .popup)
    }
}

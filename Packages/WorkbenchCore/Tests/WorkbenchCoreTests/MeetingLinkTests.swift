import Foundation
import Testing

@testable import WorkbenchCore

struct MeetingLinkTests {
    @Test(arguments: [
        ("Join with Google Meet: https://meet.google.com/abc-defg-hij", "Google Meet"),
        ("Zoom https://us02web.zoom.us/j/81234567890?pwd=xyz Meeting ID: 812 3456 7890", "Zoom"),
        ("<https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0>", "Microsoft Teams"),
        ("Join: https://acme.webex.com/acme/j.php?MTID=m1", "Webex"),
    ])
    func aCallLinkInTheNotesIsFoundWithItsService(text: String, service: String) throws {
        let url = try #require(MeetingLink.find(in: [nil, "Room 4B", text]))
        #expect(MeetingLink.service(of: url) == service)
    }

    @Test func otherLinksAreNotCallsAndTheEventLinkComesFirst() {
        #expect(
            MeetingLink.find(in: ["Agenda: https://docs.google.com/document/d/1", "https://zoom.us/pricing"]) == nil)
        #expect(MeetingLink.find(in: ["https://meet.google.com/"]) == nil)
        let first = MeetingLink.find(in: ["https://meet.google.com/aaa-bbbb-ccc", "https://zoom.us/j/1"])
        #expect(first?.absoluteString == "https://meet.google.com/aaa-bbbb-ccc")
        let meeting = Meeting(
            id: "1", calendar: "c", title: "Sync", start: t0, end: t0, joinURL: URL(string: "https://zoom.us/j/1"))
        #expect(meeting.joinService == "Zoom")
    }

    @Test func aServiceWeDoNotKnowJoinsThroughTheEventsOwnLinkButNeverANotesLink() throws {
        let url = try #require(
            MeetingLink.find(
                in: ["https://video.example.org/room/standup", nil, "Agenda https://docs.example.org/a"],
                orAnyLinkIn: ["https://video.example.org/room/standup", nil]))
        #expect(url.absoluteString == "https://video.example.org/room/standup" && MeetingLink.service(of: url) == nil)
        #expect(
            MeetingLink.find(in: [nil, "Room 4B", "https://docs.example.org/a"], orAnyLinkIn: [nil, "Room 4B"]) == nil)
        #expect(
            MeetingLink.find(
                in: ["https://video.example.org/x", "https://meet.google.com/aaa-bbbb-ccc"],
                orAnyLinkIn: ["https://video.example.org/x"])?.host() == "meet.google.com")
    }
}

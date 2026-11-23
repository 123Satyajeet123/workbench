import Foundation
import Testing

@testable import WorkbenchCore

struct CallSourceTests {
    @Test(arguments: [
        (
            "Google Chrome", "com.google.Chrome", "Meet - Weekly sync - Google Chrome",
            "https://meet.google.com/abc-defg-hij",
            "Google Meet · Weekly sync"
        ),
        ("Google Chrome", "com.google.Chrome", "Meet - abc-defg-hij", "meet.google.com/abc-defg-hij", "Google Meet"),
        (
            "Brave Browser", "com.brave.Browser", "Meet - Camera and microphone recording", "https://meet.google.com/x",
            "Google Meet"
        ),
        ("zoom.us", "us.zoom.xos", "Zoom Meeting", "", "Zoom"),
        (
            "Microsoft Teams", "com.microsoft.teams2", "Design review | Microsoft Teams", "",
            "Microsoft Teams · Design review"
        ),
        ("WhatsApp", "net.whatsapp.WhatsApp", "WhatsApp", "", "WhatsApp"),
        ("Arc", "company.thebrowser.Browser", "Standup", "https://app.slack.com/huddle/T1/C2", "Slack · Standup"),
        ("Arc", "company.thebrowser.Browser", "Inbox", "https://app.slack.com/client/T1", "Arc · Inbox"),
        ("Riverside", "fm.riverside", "Episode 4", "", "Riverside · Episode 4"),
        ("In person", "in-person", "", "", "In person"),
    ])
    func aCallIsTaggedWithTheServiceAndItsMeetingName(
        app: String, bundleID: String, title: String, address: String, label: String
    ) {
        #expect(CallSource.identify(app: app, bundleID: bundleID, windowTitle: title, address: address).label == label)
    }
}

struct CallTranscriptTests {
    @Test func bothSidesInterleaveByTimeAndARunOfOneSpeakerIsOneLine() {
        let lines = CallTranscript.merge(
            me: [
                TimedText(start: 0, text: "Hi Asha."), TimedText(start: 9, text: "Ship it Friday?"),
                TimedText(start: 12, text: "  "),
            ],
            them: [
                TimedText(start: 3, text: "Hey!"), TimedText(start: 5, text: "Quick update."),
                TimedText(start: 14, text: "Yes, Friday."),
            ])
        #expect(
            lines == [
                CallLine(speaker: .me, start: 0, text: "Hi Asha."),
                CallLine(speaker: .them, start: 3, text: "Hey! Quick update."),
                CallLine(speaker: .me, start: 9, text: "Ship it Friday?"),
                CallLine(speaker: .them, start: 14, text: "Yes, Friday."),
            ])
        #expect(
            CallTranscript.text(Array(lines.prefix(2)), me: "Shivansh (You)", them: "Them")
                == "[00:00] Shivansh (You): Hi Asha.\n[00:03] Them: Hey! Quick update.")
        #expect(CallTranscript.clock(3725) == "1:02:05")
    }
}

struct CallNoteStoreTests {
    private func recording(_ store: Store) throws -> Recording {
        try store.startRecording(
            app: "Google Chrome", bundleID: "com.google.Chrome",
            source: CallSource(service: "Google Meet", title: "Weekly sync"), grant: grant(.call))
    }

    @Test func aRecordingKeepsWhereItCameFromAndItsNotes() throws {
        let store = try makeStore()
        let call = try recording(store)
        try store.finishRecording(call.id)
        #expect(try store.queries.recordings().first?.source.label == "Google Meet · Weekly sync")
        #expect(try store.queries.callNotes().isEmpty)

        let lines = [CallLine(speaker: .me, start: 0, text: "Hi")]
        try store.saveTranscript(of: call.id, lines: lines)
        let summary = CallSummary(
            summary: "Agreed to ship.", decisions: ["Ship Friday"], actions: [.init(owner: "Asha", text: "Send build")])
        try store.saveSummary(of: call.id, summary: summary, run: nil)
        #expect(try store.queries.callNotes()[call.id] == CallNote(transcript: lines, summary: summary))

        try store.saveTranscript(of: call.id, lines: nil, error: "No speech")
        #expect(try store.queries.callNotes()[call.id] == CallNote(transcriptError: "No speech"))
    }

    @Test func deletingACallDeletesItsTranscriptAndSummary() throws {
        let store = try makeStore()
        let call = try recording(store)
        try store.finishRecording(call.id)
        try store.saveTranscript(of: call.id, lines: [CallLine(speaker: .them, start: 1, text: "Bye")])
        try store.delete(.kind(.call, before: day(1)))
        #expect(try store.queries.callNotes().isEmpty)
    }

    @Test func anOlderRecordingWithoutASourceIsTaggedWithItsApp() throws {
        let store = try makeStore()
        _ = try store.startRecording(app: "Brave", bundleID: "com.brave.Browser", grant: grant(.call))
        #expect(try store.queries.recordings().first?.source.label == "Brave")
    }
}

struct CallDetectorTests {
    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func anAppHoldingTheMicrophoneForAFewSecondsIsACallUntilItLetsGoForAWhile() {
        var detector = CallDetector()
        #expect(detector.update(listening: ["us.zoom.xos"], at: at(0)).isEmpty)
        #expect(detector.update(listening: ["us.zoom.xos"], at: at(2)).isEmpty)
        #expect(detector.update(listening: ["us.zoom.xos"], at: at(6)) == [.started("us.zoom.xos")])
        #expect(detector.update(listening: ["us.zoom.xos"], at: at(8)).isEmpty)
        #expect(detector.update(listening: [], at: at(10)).isEmpty)
        #expect(detector.update(listening: ["us.zoom.xos"], at: at(20)).isEmpty)
        #expect(detector.update(listening: [], at: at(30)).isEmpty)
        #expect(detector.update(listening: [], at: at(36)) == [.ended("us.zoom.xos")])
        #expect(detector.calls.isEmpty)
    }

    @Test func aShortBlipAndAVoiceMemoAreNeverCalls() {
        var detector = CallDetector()
        _ = detector.update(listening: ["com.google.Chrome", "com.apple.VoiceMemos"], at: at(0))
        _ = detector.update(listening: ["com.apple.VoiceMemos"], at: at(2))
        #expect(detector.update(listening: ["com.apple.VoiceMemos"], at: at(30)).isEmpty)
        #expect(detector.calls.isEmpty)
    }
}

struct RecordingPlaceTests {
    @Test func newCallsGoToTheChosenFolderAndAreStillFoundAndDeleted() throws {
        let store = try makeStore()
        let chosen = temporaryDirectory().appending(path: "Calls")
        #expect(try store.recordingsPlace() == nil)
        try store.setRecordingsPlace(chosen)
        let call = try store.startRecording(app: "zoom.us", bundleID: "us.zoom.xos", grant: grant(.call))
        #expect(call.folder.deletingLastPathComponent().standardizedFileURL == chosen.standardizedFileURL)
        #expect(try FileManager.default.attributesOfItem(atPath: call.folder.path)[.posixPermissions] as? Int == 0o700)
        try store.finishRecording(call.id)
        #expect(try store.queries.recordings().first?.folder.standardizedFileURL == call.folder.standardizedFileURL)

        try store.setRecordingsPlace(nil)
        let back = try store.startRecording(app: "zoom.us", bundleID: "us.zoom.xos", grant: grant(.call))
        #expect(
            back.folder.deletingLastPathComponent().path(percentEncoded: false).hasPrefix(
                store.defaultRecordingsPlace.path))
        try store.finishRecording(back.id)

        try store.delete(.kind(.call, before: day(1)))
        #expect(!FileManager.default.fileExists(atPath: call.folder.path))
        #expect(!FileManager.default.fileExists(atPath: back.folder.path))
        #expect(FileManager.default.fileExists(atPath: chosen.path))
    }
}

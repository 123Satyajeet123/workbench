import AVFoundation
import CaptureService
import Foundation
import Kernel
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

private nonisolated final class FakeListener: CallListener {
    let ready: ListenerReadiness
    let said: [String: [TimedText]]
    let fails: Bool
    let heard = Mutex<[String]>([])

    init(ready: ListenerReadiness = .ready, said: [String: [TimedText]] = [:], fails: Bool = false) {
        self.ready = ready
        self.said = said
        self.fails = fails
    }

    func readiness() async -> ListenerReadiness { ready }
    func install() async throws {}

    func segments(_ audio: URL) async throws -> [TimedText] {
        heard.withLock { $0.append(audio.lastPathComponent) }
        if fails { throw CocoaError(.fileReadCorruptFile) }
        return said[audio.lastPathComponent] ?? []
    }
}

private let testOwner = { try PersonID("test-owner") }

private let summaryReply = #"""
    {"points":[{"text":"Asha gave a quick update.","cites":[2],"quote":"quick update"},
     {"text":"They will ship on Friday.","cites":[9],"quote":"Friday then"}]}
    """#

@MainActor struct CallNotesTests {
    private func call(in store: Store, seconds: Double = 2) throws -> Recording {
        try store.savePolicy(CapturePolicy(switches: [.call: true]))
        let grant = try #require(
            CapturePolicy(switches: [.call: true])
                .authorize(CaptureRequest(kind: .call, label: "com.google.Chrome", liveSession: true), at: Date())
                .grant)
        let recording = try store.startRecording(
            app: "Google Chrome", bundleID: "com.google.Chrome",
            source: CallSource(service: "Google Meet", title: "Weekly sync"), grant: grant)
        for name in ["me-001.m4a", "me-002.m4a", "them-001.m4a"] {
            try silence(seconds, at: recording.folder.appending(path: name))
        }
        try store.finishRecording(recording.id)
        return recording
    }

    private func silence(_ seconds: Double, at url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(
            forWriting: url,
            settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1])
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(16_000 * seconds)))
        buffer.frameLength = buffer.frameCapacity
        try file.write(from: buffer)
    }

    @Test func aFollowUpYouTookOnInACallLandsOnTodayAndItsTickClosesIt() async throws {
        let store = try scratchStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        _ = try call(in: store)
        let listener = FakeListener(said: [
            "me-001.m4a": [TimedText(start: 0.5, text: "Sure, I will send the deck tonight.")],
            "them-001.m4a": [TimedText(start: 0.2, text: "Can you send the deck?")],
        ])
        let noTime =
            #"{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""}"#
        let followUps = #"""
            {"items":[
             {"person":"Shivansh","kind":"commitment","text":"Send the deck","when":\#(noTime),"asks":"founder",
              "relation":{"kind":"new","handle":"","outcome":""},"cite":@send the deck tonight@,
              "quote":"I will send the deck tonight"},
             {"person":"Them","kind":"commitment","text":"Book the room","when":\#(noTime),"asks":"team",
              "relation":{"kind":"new","handle":"","outcome":""},"cite":@Can you send@,"quote":"book the room"}]}
            """#
        let model = KeyedModel([
            "write their notes on it": #"{"points":[]}"#,
            HelperSpec.callFollowUps.brief: followUps,
        ])
        let notes = CallNotes(
            store: store, listener: listener, founder: { "Shivansh" }, owner: testOwner,
            makeModel: { _ in RecordedModel(model, store: store) })
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Shivansh" }, notifier: FakeNotifier())
        let today = TodayModel(store: store, crew: crew)
        notes.onFollowUps = today.refresh
        await notes.start()

        let task = HelperSpec.callFollowUps.task
        #expect(today.callFollowUps.map(today.title(of:)) == ["Send the deck"], "words nobody said stay off Today")
        #expect(today.needs.first?.reason == .asks && today.needs.first?.item.task == task)
        #expect(ReviewModel(store: store, crew: crew).items.isEmpty, "a call's follow-up is not a machine's finding")

        today.perform(.done, on: today.callFollowUps, text: "Done")
        #expect(today.isDone(today.callFollowUps) && !today.needs.contains { $0.item.task == task })
    }

    @Test func aCallIsNamedAfterItsCalendarMeetingAndItsOneGuestNamesThem() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let listener = FakeListener(said: ["them-001.m4a": [TimedText(start: 1, text: "Hey, quick update.")]])
        let model = ScriptedModel(summaryReply)
        let asked = Mutex<[DateInterval]>([])
        let intro = Meeting(
            id: "1", calendar: "work", title: "Acme intro", start: recording.startedAt.addingTimeInterval(-60),
            end: recording.startedAt.addingTimeInterval(1800),
            attendees: [.init(name: "", email: "meera@acme.in"), .init(name: "Me", email: "me@x.in", isMe: true)])
        let notes = CallNotes(
            store: store, listener: listener, founder: { "Shivansh" }, owner: testOwner,
            makeModel: { _ in RecordedModel(model, store: store) },
            meetings: { interval in
                asked.withLock { $0.append(interval) }
                return [intro]
            })
        await notes.start()

        let named = try #require(try store.queries.recordings().first)
        #expect(named.source.label == "Google Meet · Acme intro" && named.them == "meera@acme.in")
        let input = try #require(model.inputs.withLock { $0.last })
        #expect(input.contains("Invited: meera@acme.in") && input.contains("meera@acme.in: Hey, quick update."))
        #expect(asked.withLock { $0.first?.contains(recording.startedAt) } == true)

        await notes.processPending()
        #expect(asked.withLock { $0.count } == 1, "a call is looked up once")
    }

    @Test func aCallIsLookedUpAgainLaterWhenTheCalendarCannotBeRead() async throws {
        let store = try scratchStore()
        _ = try call(in: store)
        let notes = CallNotes(store: store, listener: nil, founder: { "" }, owner: testOwner, meetings: { _ in nil })
        await notes.start()
        #expect(try store.queries.recordings().first?.guests == nil)
    }

    @Test func aSavedCallIsTranscribedAsYouAndThemThenSummarized() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let listener = FakeListener(said: [
            "me-001.m4a": [TimedText(start: 0.5, text: "Hi Asha.")],
            "me-002.m4a": [TimedText(start: 1, text: "Friday then.")],
            "them-001.m4a": [TimedText(start: 1, text: "Hey, quick update.")],
        ])
        let model = ScriptedModel(summaryReply)
        let notes = CallNotes(
            store: store, listener: listener, founder: { "Shivansh" }, owner: testOwner,
            makeModel: { _ in RecordedModel(model, store: store) })
        await notes.start()

        let note = try #require(notes.notes[recording.id])
        let lines = try #require(note.transcript)
        #expect(lines.map(\.speaker) == [.me, .them, .me])
        #expect(lines.last?.text == "Friday then." && abs((lines.last?.start ?? 0) - 3) < 0.25)
        #expect(note.points?.map(\.text) == ["Asha gave a quick update."], "a point citing no line is dropped")
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Call: Google Meet · Weekly sync"))
        #expect(input.contains("Shivansh (You): Hi Asha."))
        #expect(input.contains("Them: Hey, quick update."))
        #expect(try store.queries.runs().first?.task == CallSummarizer.task)

        await notes.processPending()
        #expect(listener.heard.withLock { $0.count } == 3 && model.inputs.withLock { $0.count } == 1)
    }

    @Test func aSilentCallSaysSoAndIsNeverSentToTheModel() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let model = ScriptedModel(summaryReply)
        let notes = CallNotes(
            store: store, listener: FakeListener(), founder: { "Shivansh" }, owner: testOwner,
            makeModel: { _ in RecordedModel(model, store: store) })
        await notes.start()
        #expect(notes.notes[recording.id] == CallNote(transcript: []))
        #expect(model.inputs.withLock { $0.isEmpty })
    }

    @Test func aFailedTranscriptCanBeTriedAgain() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let notes = CallNotes(store: store, listener: FakeListener(fails: true), founder: { "" }, owner: testOwner)
        await notes.start()
        #expect(notes.notes[recording.id]?.transcriptError != nil)

        let fixed = CallNotes(
            store: store, listener: FakeListener(said: ["them-001.m4a": [TimedText(start: 0, text: "Bye")]]),
            founder: { "" }, owner: testOwner,
            makeModel: { _ in RecordedModel(ScriptedModel(summaryReply), store: store) })
        await fixed.checkSpeech()
        await fixed.retry(recording)
        #expect(fixed.notes[recording.id]?.transcript?.first?.text == "Bye")
        #expect(fixed.notes[recording.id]?.points != nil)
    }

    @Test func withoutTheSpeechModelNothingIsTranscribedAndTheDownloadIsOffered() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let listener = FakeListener(ready: .needsDownload)
        let notes = CallNotes(store: store, listener: listener, founder: { "" }, owner: testOwner)
        await notes.start()
        #expect(notes.speech == .needsDownload)
        #expect(notes.notes[recording.id] == nil && listener.heard.withLock { $0.isEmpty })

        let old = CallNotes(store: store, listener: nil, founder: { "" }, owner: testOwner)
        await old.start()
        #expect(old.speech == .unavailable("Transcripts need macOS 26 or newer."))
    }
}

@MainActor struct RecordingsPlaceSettingTests {
    @Test func withoutADefaultTheStoreKeepsItsOwnFolder() throws {
        let store = try scratchStore()
        let notes = CallNotes(store: store, listener: nil, founder: { "" }, owner: testOwner)
        let saved = try store.recordingsPlace()
        #expect(notes.savedIn == store.defaultRecordingsPlace && saved == nil)
    }
}

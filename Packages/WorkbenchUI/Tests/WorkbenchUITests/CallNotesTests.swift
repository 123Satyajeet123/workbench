import AVFoundation
import Foundation
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

private let summaryReply = #"""
    {"summary":"Asha shared the release plan.","decisions":["Ship on Friday"],
     "actions":[{"owner":"Asha","text":"Send the build by Thursday"}]}
    """#

@MainActor struct CallNotesTests {
    private func call(in store: Store, seconds: Double = 2) throws -> Recording {
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
            store: store, listener: listener, founder: { "Shivansh" },
            makeModel: { _ in RecordedModel(model, store: store) })
        await notes.start()

        let note = try #require(notes.notes[recording.id])
        let lines = try #require(note.transcript)
        #expect(lines.map(\.speaker) == [.me, .them, .me])
        #expect(lines.last?.text == "Friday then." && abs((lines.last?.start ?? 0) - 3) < 0.25)
        #expect(note.summary?.decisions == ["Ship on Friday"])
        #expect(note.summary?.actions.first?.owner == "Asha")
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("Call: Google Meet · Weekly sync"))
        #expect(input.contains("Shivansh (You): Hi Asha."))
        #expect(input.contains("Them: Hey, quick update."))
        #expect(try store.queries.runs().first?.task == CallNotes.task)

        await notes.processPending()
        #expect(listener.heard.withLock { $0.count } == 3 && model.inputs.withLock { $0.count } == 1)
    }

    @Test func aSilentCallSaysSoAndIsNeverSentToTheModel() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let model = ScriptedModel(summaryReply)
        let notes = CallNotes(
            store: store, listener: FakeListener(), founder: { "Shivansh" },
            makeModel: { _ in RecordedModel(model, store: store) })
        await notes.start()
        #expect(notes.notes[recording.id] == CallNote(transcriptError: CallNotes.noSpeech))
        #expect(model.inputs.withLock { $0.isEmpty })
    }

    @Test func aFailedTranscriptCanBeTriedAgain() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let notes = CallNotes(store: store, listener: FakeListener(fails: true), founder: { "" })
        await notes.start()
        #expect(notes.notes[recording.id]?.transcriptError != nil)

        let fixed = CallNotes(
            store: store, listener: FakeListener(said: ["them-001.m4a": [TimedText(start: 0, text: "Bye")]]),
            founder: { "" }, makeModel: { _ in RecordedModel(ScriptedModel(summaryReply), store: store) })
        await fixed.checkSpeech()
        await fixed.retry(recording)
        #expect(fixed.notes[recording.id]?.transcript?.first?.text == "Bye")
        #expect(fixed.notes[recording.id]?.summary != nil)
    }

    @Test func withoutTheSpeechModelNothingIsTranscribedAndTheDownloadIsOffered() async throws {
        let store = try scratchStore()
        let recording = try call(in: store)
        let listener = FakeListener(ready: .needsDownload)
        let notes = CallNotes(store: store, listener: listener, founder: { "" })
        await notes.start()
        #expect(notes.speech == .needsDownload)
        #expect(notes.notes[recording.id] == nil && listener.heard.withLock { $0.isEmpty })

        let old = CallNotes(store: store, listener: nil, founder: { "" })
        await old.start()
        #expect(old.speech == .unavailable("Transcripts need macOS 26 or newer."))
    }
}

@MainActor struct RecordingsPlaceSettingTests {
    @Test func callsGoToTheDefaultFolderUntilTheFounderPicksAnotherAndCanGoBack() throws {
        let store = try scratchStore()
        let documents = scratchFolder().appending(path: "Workbench/Recordings")
        let notes = CallNotes(store: store, listener: nil, founder: { "" }, defaultPlace: documents)
        #expect(notes.savedIn.standardizedFileURL == documents.standardizedFileURL && notes.isDefaultPlace)

        let mine = scratchFolder()
        notes.saveRecordings(in: mine)
        #expect(!notes.isDefaultPlace)
        let again = CallNotes(store: store, listener: nil, founder: { "" }, defaultPlace: documents)
        #expect(again.savedIn.standardizedFileURL == mine.standardizedFileURL)

        again.useDefaultPlace()
        let saved = try store.recordingsPlace()
        #expect(again.isDefaultPlace && saved?.standardizedFileURL == documents.standardizedFileURL)
    }

    @Test func withoutADefaultTheStoreKeepsItsOwnFolder() throws {
        let store = try scratchStore()
        let notes = CallNotes(store: store, listener: nil, founder: { "" })
        let saved = try store.recordingsPlace()
        #expect(notes.savedIn == store.defaultRecordingsPlace && saved == nil)
    }
}

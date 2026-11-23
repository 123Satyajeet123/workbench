import AppKit
import Foundation
import LocalSources
import Observation
import WorkbenchCore

typealias MeetingLookup = @MainActor (DateInterval) async -> [Meeting]?

enum ListenerReadiness: Equatable {
    case ready, needsDownload, downloading, unsupported
}

protocol CallListener: Sendable {
    func readiness() async -> ListenerReadiness
    func install() async throws
    func segments(_ audio: URL) async throws -> [TimedText]
}

@available(macOS 26, *)
nonisolated struct AppleListener: CallListener {
    func readiness() async -> ListenerReadiness {
        switch await AppleTranscriber.english().status() {
        case .installed: .ready
        case .supported: .needsDownload
        case .downloading: .downloading
        default: .unsupported
        }
    }

    func install() async throws { try await AppleTranscriber.english().install() }

    func segments(_ audio: URL) async throws -> [TimedText] { try await AppleTranscriber.english().segments(audio) }
}

@MainActor @Observable
final class CallNotes {
    enum Speech: Equatable {
        case checking, ready, needsDownload, downloading
        case unavailable(String)
    }

    static let task = "call.summary"
    static let noSpeech = "No speech was heard in this call."

    private(set) var speech = Speech.checking
    private(set) var notes: [Int64: CallNote] = [:]
    private(set) var working: Set<Int64> = []
    private(set) var place: URL?
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let makeModel: ModelMaker
    @ObservationIgnored private let listener: (any CallListener)?
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let meetings: MeetingLookup
    @ObservationIgnored let defaultPlace: URL?
    @ObservationIgnored var onFollowUps: () -> Void = {}

    static let documentsPlace = URL.documentsDirectory.appending(path: "Workbench/Recordings")

    init(
        store: Store, listener: (any CallListener)?, founder: @escaping () -> String,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, defaultPlace: URL? = nil,
        meetings: @escaping MeetingLookup = { _ in nil }
    ) {
        self.store = store
        self.meetings = meetings
        self.listener = listener
        self.founder = founder
        self.defaultPlace = defaultPlace
        self.makeModel = ModelMaker(store: store, make: makeModel)
        if let defaultPlace, (try? store.recordingsPlace()) == nil { saveRecordings(in: defaultPlace) }
        refresh()
    }

    static func appleListener() -> (any CallListener)? {
        if #available(macOS 26, *) { AppleListener() } else { nil }
    }

    func refresh() {
        problems.attempt("read call notes", clearing: false) {
            notes = try store.queries.callNotes()
            place = try store.recordingsPlace()
        }
    }

    var savedIn: URL { place ?? store.defaultRecordingsPlace }

    var isDefaultPlace: Bool { place?.standardizedFileURL == defaultPlace?.standardizedFileURL }

    func useDefaultPlace() { saveRecordings(in: defaultPlace) }

    func revealPlace() {
        problems.attempt("open the recordings folder", clearing: true) {
            try FileManager.default.createDirectory(at: savedIn, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([savedIn])
    }

    func saveRecordings(in folder: URL?) {
        problems.attempt("change where calls are saved", clearing: true) {
            try store.setRecordingsPlace(folder)
            place = try store.recordingsPlace()
        }
    }

    func start() async {
        await checkSpeech()
        await processPending()
    }

    func checkSpeech() async {
        guard let listener else {
            speech = .unavailable("Transcripts need macOS 26 or newer.")
            return
        }
        speech =
            switch await listener.readiness() {
            case .ready: .ready
            case .needsDownload: .needsDownload
            case .downloading: .downloading
            case .unsupported: .unavailable("This Mac can't transcribe English yet.")
            }
    }

    func download() async {
        guard let listener else { return }
        speech = .downloading
        do {
            try await listener.install()
        } catch {
            problems.show("The English speech model did not download: \(error.localizedDescription)")
        }
        await start()
    }

    func retry(_ recording: Recording) async {
        problems.attempt("clear the old notes", clearing: true) {
            try store.forgetNote(of: recording.id)
            try store.dropCallActions(of: recording.id)
        }
        onFollowUps()
        refresh()
        await processPending()
    }

    func processPending() async {
        await nameFromCalendar()
        guard speech == .ready else { return }
        let recordings = (try? store.queries.recordings()) ?? []
        for recording in recordings.reversed() where recording.state == .saved {
            guard !working.contains(recording.id) else { continue }
            if notes[recording.id] == nil {
                await transcribe(recording)
            } else if let note = notes[recording.id], let lines = note.transcript, note.summary == nil,
                note.summaryError == nil
            {
                await summarize(recording, lines: lines)
            }
        }
    }

    private func nameFromCalendar() async {
        let recordings = (try? store.queries.recordings()) ?? []
        for recording in recordings where recording.state == .saved && recording.guests == nil {
            let end = recording.endedAt ?? recording.startedAt
            let around = DateInterval(
                start: recording.startedAt.addingTimeInterval(-Self.calendarReach),
                end: end.addingTimeInterval(Self.calendarReach))
            guard let found = await meetings(around) else { return }
            problems.attempt("name the call", clearing: false) {
                try store.nameRecording(recording.id, after: Meeting.during(recording.startedAt, end, in: found))
            }
        }
        refresh()
    }

    static let calendarReach: TimeInterval = 3600

    private func transcribe(_ recording: Recording) async {
        guard let listener else { return }
        working.insert(recording.id)
        defer { working.remove(recording.id) }
        let tracks = CallTracks.files(in: recording.folder)
        do {
            let lines = CallTranscript.merge(
                me: try await timed(tracks.me, by: listener), them: try await timed(tracks.them, by: listener))
            try store.saveTranscript(
                of: recording.id, lines: lines.isEmpty ? nil : lines,
                error: lines.isEmpty ? Self.noSpeech : nil)
            refresh()
            if !lines.isEmpty { await summarize(recording, lines: lines, alreadyWorking: true) }
        } catch {
            problems.attempt("save the transcript error", clearing: false) {
                try store.saveTranscript(of: recording.id, lines: nil, error: error.localizedDescription)
            }
            refresh()
        }
    }

    private func timed(_ files: [URL], by listener: any CallListener) async throws -> [TimedText] {
        var offset: TimeInterval = 0
        var all: [TimedText] = []
        for file in files {
            all += try await listener.segments(file).map { TimedText(start: $0.start + offset, text: $0.text) }
            offset += CallTracks.duration(of: file)
        }
        return all
    }

    private func summarize(_ recording: Recording, lines: [CallLine], alreadyWorking: Bool = false) async {
        if !alreadyWorking { working.insert(recording.id) }
        defer { if !alreadyWorking { working.remove(recording.id) } }
        let me = founderLabel(founder())
        do {
            let (summary, run) = try await makeModel.current().generate(
                CallSummary.self, schema: CallSummary.schema, task: Self.task, instructions: Self.instructions,
                input: Self.input(recording, lines: lines, me: me), holding: [.call])
            try store.saveSummary(of: recording.id, summary: summary, run: run)
            try store.saveCallActions(of: recording, lines: lines, summary: summary, founder: me, run: run)
            onFollowUps()
        } catch {
            problems.attempt("save the summary error", clearing: false) {
                try store.saveSummary(of: recording.id, summary: nil, run: nil, error: error.localizedDescription)
            }
        }
        refresh()
    }

    static func input(_ recording: Recording, lines: [CallLine], me: String) -> String {
        let minutes = recording.endedAt.map { Int(($0.timeIntervalSince(recording.startedAt) / 60).rounded()) }
        let when = recording.startedAt.formatted(date: .abbreviated, time: .shortened)
        var header = ["Call: \(recording.source.label)", "When: \(when)" + (minutes.map { ", \($0) min" } ?? "")]
        header.append("Founder: \(me)")
        if let guests = recording.guests, !guests.isEmpty {
            header.append("Invited: \(guests.joined(separator: ", "))")
        }
        return (header + ["", CallTranscript.text(lines, me: me, them: recording.them)]).joined(separator: "\n")
    }

    static let instructions = """
        You read the transcript of one call the founder recorded and write their notes on it.
        The founder's own lines are marked with the name after "Founder:". Every other voice is marked "Them", which \
        can be several people, or with the guest's name when one guest was invited. Use a name for "Them" only when \
        one is said; the invited list says who was asked to join.
        summary: two to four plain sentences on what the call was about and where it ended.
        decisions: each thing that was agreed or settled, one short line each.
        actions: each concrete follow-up someone took on. owner is who does it: the founder's name as given after \
        "Founder:", a person's name when it was said, or "Them". text says what, with any date that was said. due is \
        that date as YYYY-MM-DD, worked out from the day of the call, or empty when no day was said. quote is the \
        exact words from one transcript line where it was taken on, copied character for character.
        Use only what was said in the call. Leave a list empty when there is nothing for it. Speech recognition makes \
        mistakes; when a word is clearly misheard, write what was meant only if it is obvious.
        """
}

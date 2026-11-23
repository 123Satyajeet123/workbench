import AppKit
import Foundation
import Kernel
import LocalSources
import Observation
import WorkbenchCore

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

/// Transcribes each saved call on this Mac into its evidence lines, then asks for its notes (`CallSummarizer`).
@MainActor @Observable
final class CallNotes {
    enum Speech: Equatable {
        case checking, ready, needsDownload, downloading
        case unavailable(String)
    }

    static let noSpeech = "No speech was heard in this call."

    private(set) var speech = Speech.checking
    private(set) var notes: [Int64: CallNote] = [:]
    private(set) var working: Set<Int64> = []
    /// The folder the founder chose for new recordings; nil keeps them in the store's own folder.
    private(set) var place: URL?
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let makeModel: ModelMaker
    @ObservationIgnored private let listener: (any CallListener)?
    @ObservationIgnored private let founder: () -> String
    @ObservationIgnored private let owner: () throws -> PersonID

    init(
        store: Store, listener: (any CallListener)?, founder: @escaping () -> String,
        owner: @escaping () throws -> PersonID, makeModel: ((ModelChoice) -> RecordedModel)? = nil
    ) {
        self.store = store
        self.listener = listener
        self.founder = founder
        self.owner = owner
        self.makeModel = ModelMaker(store: store, make: makeModel)
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

    var isDefaultPlace: Bool { place == nil }

    func useDefaultPlace() { saveRecordings(in: nil) }

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

    /// A failed transcript is made again; failed notes are asked for again.
    func retry(_ recording: Recording) async {
        guard notes[recording.id]?.transcriptError != nil else { return await summarize(recording) }
        problems.attempt("clear the transcript error", clearing: true) {
            try store.setTranscriptError(of: recording.id, nil)
        }
        refresh()
        await processPending()
    }

    func processPending() async {
        guard speech == .ready else { return }
        let recordings = (try? store.queries.recordings()) ?? []
        for recording in recordings.reversed() where recording.state == .saved {
            guard !working.contains(recording.id) else { continue }
            let note = notes[recording.id]
            if note == nil {
                await transcribe(recording)
            } else if note?.transcript?.isEmpty == false, note?.summary == nil, note?.summaryError == nil {
                await summarize(recording)
            }
        }
    }

    private func transcribe(_ recording: Recording) async {
        guard let listener else { return }
        working.insert(recording.id)
        let tracks = CallTracks.files(in: recording.folder)
        do {
            let lines = CallTranscript.merge(
                me: try await timed(tracks.me, by: listener), them: try await timed(tracks.them, by: listener))
            try store.recordTranscript(lines, of: recording, owner: owner())
        } catch {
            problems.attempt("save the transcript error", clearing: false) {
                try store.setTranscriptError(of: recording.id, error.localizedDescription)
            }
        }
        working.remove(recording.id)
        refresh()
        if notes[recording.id]?.transcript?.isEmpty == false { await summarize(recording) }
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

    /// A model that fails records its run as failed, and the card shows why.
    private func summarize(_ recording: Recording) async {
        working.insert(recording.id)
        do {
            let lines = try store.queries.currentLines(
                in: [recording.container], from: .distantPast, to: .distantFuture)
            try await CallSummarizer(model: makeModel.current()).summarize(
                recording, lines: lines, me: founderLabel(founder()))
        } catch {
            problems.report("write the notes of that call", error)
        }
        working.remove(recording.id)
        refresh()
    }
}

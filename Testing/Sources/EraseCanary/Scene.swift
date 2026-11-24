import Foundation
import GRDB
import Kernel
import Lines
import Synchronization

@testable import WorkbenchCore

/// The clock of a scratch store: it stands at a moment until the demo moves it.
final class MovingClock: Sendable {
    private let moment: Mutex<Date>

    init(_ start: Date) { moment = Mutex(start) }

    var now: Date { moment.withLock { $0 } }
    func move(to date: Date) { moment.withLock { $0 = date } }
}

struct SceneError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// What the scene holds that a check needs to find again.
struct Made {
    var canaryLine = Data()
    var items: [Int64] = []
    var run: RunID = 0
    var page: PageProposalID = 0
    var home: WorkObjectID = ""
    var recordingFolder: URL?
}

/// A scratch store built through the writers the app uses: lines from six sources, then everything the model and the
/// code derive from the line that holds the canary.
final class Scene {
    static let chatA = "120300000000000001@g.us"
    static let chatB = "120300000000000002@g.us"
    static let mailLabel = "Inbox Example"
    static let browser = "com.example.browser"
    static let site = "pages.example.test"
    static let day = 86_400.0

    private(set) var store: Store
    let words: Words
    let clock: MovingClock
    let now: Date
    let old: Date
    let owner: PersonID
    var made = Made()
    var machine: Machine?
    var folder: WorkObject?
    var policy = CapturePolicy(
        switches: [.whatsapp: true, .mail: true, .call: true, .screen: true, .screenText: true],
        allowList: [.whatsapp: [chatA, chatB], .mail: [mailLabel]], browsers: [browser: "Example Browser"])

    let directory: URL

    /// Builds the scene. The old lines are written 40 days before `now`, the new ones at `now`.
    init(in directory: URL, words: Words, busyTimeout: TimeInterval = 10) throws {
        self.words = words
        self.directory = directory
        now = Date()
        old = now.addingTimeInterval(-40 * Self.day)
        clock = MovingClock(old)
        let moving = clock
        store = try Store(
            directory: directory, clock: { moving.now }, busyTimeout: busyTimeout, isAudited: { _ in false })
        owner = try PersonID("owner")
        try store.savePolicy(policy)
    }

    /// Closes the store and opens the folder again, as a new start of the app does.
    func reopen(busyTimeout: TimeInterval = 10) throws {
        try store.writer.close()
        let moving = clock
        store = try Store(
            directory: directory, clock: { moving.now }, busyTimeout: busyTimeout, isAudited: { _ in false })
    }

    func build() async throws {
        try writeChats()
        try await writeMail()
        try await writeNote()
        try writeFile()
        try await writeCall()
        try await writePage()
        try await readAndDerive()
        try KilledCall.leaveInput(
            of: "Asha Example: please send \(words.canary) to Ravi Example by Friday",
            in: directory.appending(path: Store.agentWorkFolder))
        guard ByteScan.hits(of: words.canary, under: store.agentWork).count == 1 else {
            throw SceneError("the killed call left no file with the canary: the demo cannot show the sweep")
        }
        try reopen()
        clock.move(to: now)
        try writeNewChatLine()
    }

    // MARK: Lines through the writers of the app

    func grant(_ kind: SourceKind, _ label: String?) throws -> CaptureGrant {
        guard let grant = policy.authorize(CaptureRequest(kind: kind, label: label), at: clock.now).grant else {
            throw SceneError("no grant for \(kind) \(label)")
        }
        return grant
    }

    static func groupKey(chat: String, stanza: String) throws -> EntityKey {
        try EntityKey.whatsAppGroup(chat: chat, author: .member("a@s.whatsapp.net"), stanzaID: stanza)
    }

    static func groupLine(chat: String, stanza: String, text: String, at time: Date) throws -> ObservedLine {
        ObservedLine(
            line: Line(
                entity: try groupKey(chat: chat, stanza: stanza), text: text, readerVersion: "scene 1"),
            eventTime: UTCInstant(time), actor: "a@s.whatsapp.net", messageRef: stanza)
    }

    static func groupTombstone(chat: String, stanza: String, at time: Date) throws -> ObservedLine {
        ObservedLine(
            line: .tombstone(entity: try groupKey(chat: chat, stanza: stanza), readerVersion: "scene 1"),
            eventTime: UTCInstant(time), actor: "a@s.whatsapp.net", messageRef: stanza)
    }

    func record(_ lines: [ObservedLine], chat: String) throws {
        let audience = AudienceDigest(owner: WhatsAppAudience.owner, members: ["a@s.whatsapp.net"])
        _ = try store.record(
            SourceReading(
                grant: try grant(.whatsapp, chat), label: chat, container: chat, audience: audience, lines: lines,
                cursorAfter: nil, readerVersion: "scene 1"), of: .whatsAppChat, owner: owner)
    }

    private func writeChats() throws {
        let stamp = old
        try record(
            [
                try Self.groupLine(
                    chat: Self.chatA, stanza: "A1",
                    text: "Asha Example: please send \(words.canary) to Ravi Example by Friday", at: stamp),
                try Self.groupLine(
                    chat: Self.chatA, stanza: "A2", text: "Ravi Example: the invoice \(words.sameChat) is paid",
                    at: stamp.addingTimeInterval(60)),
            ], chat: Self.chatA)
        try record(
            [
                try Self.groupLine(
                    chat: Self.chatB, stanza: "B1", text: "Asha Example: lunch \(words.otherChat) at noon",
                    at: stamp.addingTimeInterval(120))
            ], chat: Self.chatB)
        made.canaryLine =
            try store.queries.currentLines(
                in: [Self.chatA], from: .distantPast, to: .distantFuture
            ).first { $0.text.contains(words.canary) }?.lineID ?? Data()
    }

    private func writeNewChatLine() throws {
        try record(
            [
                try Self.groupLine(
                    chat: Self.chatB, stanza: "B2", text: "Ravi Example: new plan \(words.otherChat)-new", at: now)
            ], chat: Self.chatB)
    }

    private func writeMail() async throws {
        let message = MailMessage(
            context: MailContext(
                browser: "", url: "https://mail.google.com/mail/u/0/#inbox/t1", label: Self.mailLabel,
                threadId: "thread-example-1", messageId: "message-example-1"),
            sender: "asha@example.test", recipients: ["owner@example.test"], account: "owner@example.test",
            sent: old.timeIntervalSince1970, text: "Hello Ravi Example, the offer \(words.mail) stands.")
        try send(try JSONEncoder().encode(message), "mail")
    }

    private func writePage() async throws {
        let page = WebPage(
            browser: "", url: "https://\(Self.site)/post", title: "A post Example",
            text: "A page about \(words.page) and nothing else.")
        try send(try JSONEncoder().encode(page), "page")
    }

    /// The path the browser extension's messages take into the store.
    private func send(_ message: Data, _ what: String) throws {
        let reply = PageHost.answer(message, store: store, browser: Self.browser, owner: .success(owner))
        guard reply.kept else { throw SceneError("the page host kept no \(what): \(reply.error ?? "no error")") }
    }

    private func writeNote() async throws {
        let object = try store.createWorkObject(type: ObjectTypes.folder, parent: nil, name: "Notes Example")
        guard let note = NoteID(object: object.id) else { throw SceneError("no note id") }
        let block = NoteBlock(id: BlockID(), text: "My own note: remember \(words.note).")
        try await store.saveNote(NoteChange(note: note, blocks: [block], endings: [], order: [block.id]), owner: owner)
    }

    private func writeFile() throws {
        let line = try ObservedLine(
            line: Line(
                entity: EntityKey.web(site: "workbench", container: "deal-example", itemID: "file-example/1"),
                text: "Deck page about \(words.file) in the deal.", readerVersion: Store.readerVersion),
            eventTime: UTCInstant(clock.now), actor: WhatsAppAudience.owner,
            coordinate: try Coding.json(FilePlace(file: "deck-example.pdf", page: 1)))
        _ = try store.recordOwn(
            [line], of: .droppedFile, label: "deck-example.pdf", container: "deal-example", owner: owner
        ) { _ in }
    }

    private func writeCall() async throws {
        let recording = try store.startRecording(
            app: "Meet Example", bundleID: "com.example.meet", grant: try grant(.call, "com.example.meet"))
        try Data(repeating: 7, count: 4096).write(to: recording.folder.appending(path: "mix.caf"))
        made.recordingFolder = recording.folder
        try store.finishRecording(recording.id)
        let saved = try store.queries.recordings().first { $0.id == recording.id } ?? recording
        try store.recordTranscript(
            [CallLine(speaker: .them, start: 1, text: "Ravi Example says the budget \(words.call) is fixed.")],
            of: saved, owner: owner)
    }
}

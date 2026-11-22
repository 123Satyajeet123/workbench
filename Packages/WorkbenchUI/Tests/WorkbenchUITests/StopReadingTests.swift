import CaptureService
import Foundation
import LocalSources
import SQLite3
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The chat chooser's "Stop reading" control: the chat leaves the allow-list, and its lines, the run windows that name
/// them and the copies of their words go; the other chat stays. Each chat is read by its own machine, so each has its own run.
@MainActor @Suite struct StopReadingTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    private struct Scene {
        let store: Store
        let capture: CaptureService
        let team: WhatsAppSource
        let family: WhatsAppSource
    }

    private func reading(_ source: WhatsAppSource, _ store: Store, person: String, cites words: String) async {
        let reply =
            #"{"items":[{"person":"\#(person)","project":"Login","kind":"done","text":"Work","eta":"","asks":"team","stance":"said","cite":@\#(words)@,"quote":"\#(words)"}],"closes":[]}"#
        let pip = HelperModel(
            machine: .test(.team, "Pip"), source: source, store: store,
            makeModel: { _ in RecordedModel(ScriptedModel(reply), store: store) })
        await pip.read()
    }

    /// Both chats chosen and read, each by one machine, so each chat has lines, a run, an item and a quote.
    private func scene() async throws -> Scene {
        let now = noon
        let store = try scratchStore(clock: { now })
        let capture = try CaptureService(store: store)
        let container = try whatsApp(at: noon)
        try addGroupMember(3, chat: 2, jid: "d@s.whatsapp.net", name: "Dad", to: container)
        func source(_ task: String, chat: String) throws -> WhatsAppSource {
            let source = try WhatsAppSource(
                store: store, capture: capture, task: task, founder: { "Kabir" }, container: container)
            try source.loadGroups()
            try source.choose(try #require(source.groups.first { $0.jid == chat }))
            return source
        }
        let scene = Scene(
            store: store, capture: capture, team: try source(HelperSpec.team.task, chat: teamJID),
            family: try source("family-watch", chat: familyJID))
        await reading(scene.team, store, person: "Asha", cites: "login API done")
        await reading(scene.family, store, person: "Dad", cites: "dinner at 8")
        let quoted = "SELECT count(*) FROM item WHERE quote IN ('login API done', 'dinner at 8')"
        try #require(count(quoted, in: store) == 2)
        return scene
    }

    private func count(_ sql: String, in store: Store) throws -> Int {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let file = store.directory.appending(path: "workbench.sqlite").path
        try #require(sqlite3_open_v2(file, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        try #require(sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK)
        try #require(sqlite3_step(statement) == SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func copies(of word: String, in store: Store) -> Int {
        ["workbench.sqlite", "workbench.sqlite-wal"].reduce(0) { total, name in
            let data = (try? Data(contentsOf: store.directory.appending(path: name))) ?? Data()
            var found = 0
            var from = data.startIndex
            while let range = data.range(of: Data(word.utf8), in: from..<data.endIndex) {
                found += 1
                from = range.upperBound
            }
            return total + found
        }
    }

    private func lines(in chat: String, _ store: Store) throws -> Int {
        try count("SELECT count(*) FROM evidence WHERE container = '\(chat)'", in: store)
    }

    private func windows(in chat: String, _ store: Store) throws -> Int {
        try count(
            """
            SELECT count(*) FROM run_window w JOIN evidence e ON e.line_id = w.line_id WHERE e.container = '\(chat)'
            """, in: store)
    }

    @Test func theWarningSaysWhatStoppingDoes() {
        #expect(WhatsAppSource.stopReadingWarning == "Workbench erases what it stored from this chat.")
    }

    @Test func stoppingOneChatErasesItsLinesWindowsAndCopiesAndKeepsTheOther() async throws {
        let scene = try await scene()
        let store = scene.store
        #expect(try lines(in: teamJID, store) > 0 && windows(in: teamJID, store) > 0)
        #expect(try lines(in: familyJID, store) > 0 && windows(in: familyJID, store) > 0)
        #expect(copies(of: "login API done", in: store) > 0, "the words are in the lines, the quote and the run text")
        let familyWindows = try windows(in: familyJID, store)
        let teamChat = try #require(scene.team.chat)

        try WhatsAppSource.stopReading(teamChat, among: [scene.team, scene.family], capture: scene.capture)

        #expect(try lines(in: teamJID, store) == 0)
        #expect(try count("SELECT count(*) FROM run_window", in: store) == familyWindows, "the team windows are gone")
        #expect(try count("SELECT count(*) FROM run_text WHERE input LIKE '%login API done%'", in: store) == 0)
        #expect(try count("SELECT count(*) FROM item WHERE quote LIKE '%login API done%'", in: store) == 0)
        #expect(copies(of: "login API done", in: store) == 0)
        #expect(try store.currentPolicy().allowList[.whatsapp] == [familyJID])
        #expect(scene.team.chats.isEmpty && !scene.team.isReady)
        let reopened = try WhatsAppSource(
            store: store, capture: scene.capture, task: HelperSpec.team.task, founder: { "Kabir" })
        #expect(reopened.chats.isEmpty, "the choice is saved without the chat")

        #expect(try lines(in: familyJID, store) > 0)
        #expect(try windows(in: familyJID, store) == familyWindows)
        #expect(try count("SELECT count(*) FROM run_text WHERE input LIKE '%dinner at 8%'", in: store) == 1)
        #expect(try count("SELECT count(*) FROM item WHERE quote LIKE '%dinner at 8%'", in: store) == 1)
        #expect(scene.family.isReady)
    }

    @Test func stoppingTheOtherChatKeepsTheFirst() async throws {
        let scene = try await scene()
        let store = scene.store
        let teamWindows = try windows(in: teamJID, store)

        try WhatsAppSource.stopReading(
            try #require(scene.family.chat), among: [scene.team, scene.family], capture: scene.capture)

        #expect(try lines(in: familyJID, store) == 0 && windows(in: familyJID, store) == 0)
        #expect(copies(of: "dinner at 8", in: store) == 0)
        #expect(try lines(in: teamJID, store) > 0)
        #expect(try windows(in: teamJID, store) == teamWindows)
        #expect(try count("SELECT count(*) FROM item WHERE quote LIKE '%login API done%'", in: store) == 1)
        #expect(try store.currentPolicy().allowList[.whatsapp] == [teamJID])
    }
}

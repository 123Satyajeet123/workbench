import CaptureService
import Foundation
import Kernel
import LocalSources
import SQLite3
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The chooser over merged candidates. Its one provider is the Mac's WhatsApp data, each chat once. Choosing is the
/// only write.
@MainActor @Suite struct DiscoveryChooserTests {
    private struct Rig {
        let store: Store
        let capture: CaptureService
        let source: WhatsAppSource

        init(container: URL) throws {
            store = try scratchStore()
            capture = try CaptureService(store: store)
            source = try WhatsAppSource(
                store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" }, container: container)
        }

        func count(_ sql: String) throws -> Int {
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
    }

    private var noStore: URL { scratchFolder().appending(path: "no-whatsapp-here") }

    @Test func withNoStoreNoChatIsOfferedAndThePersonIsToldWhy() throws {
        let rig = try Rig(container: noStore)
        try rig.source.loadGroups()
        #expect(rig.source.groups.isEmpty && rig.source.direct.isEmpty)
        #expect(rig.source.pullProblem != nil, "the store cannot be read, and the person is told")
        #expect(try rig.store.currentPolicy().allowList[.whatsapp] == nil)
    }

    @Test func aChatTheStoreSeesIsListedOnceNothingIsStoredBeforeTheChoiceAndChoosingEndsTheQuestion() throws {
        let rig = try Rig(container: try whatsApp(at: Date(timeIntervalSince1970: 1_790_000_000)))
        try rig.source.loadGroups()
        #expect(rig.source.groups.map(\.name) == ["Team", "Family"])
        #expect(rig.source.candidates.first { $0.id == teamJID }?.seenBy == [SourceDescriptor.whatsAppChat.key])
        #expect(try rig.store.currentPolicy().allowList[.whatsapp] == nil, "nothing is allowed before the choice")
        #expect(try rig.count("SELECT count(*) FROM evidence") == 0)

        try rig.source.choose(try #require(rig.source.groups.first))
        #expect(try rig.store.currentPolicy().allowList[.whatsapp] == [teamJID])
        #expect(rig.source.chats.map(\.jid) == [teamJID])
        #expect(rig.source.candidates.isEmpty, "the choice ends the question")
    }

    @Test func aRuleChoosesGroupsFromTheCandidates() throws {
        let rig = try Rig(container: try whatsApp(at: Date(timeIntervalSince1970: 1_790_000_000)))
        try rig.source.preview(ChatSelection(nameContains: "team", directWithMembers: true))
        #expect(rig.source.matching.map(\.name) == ["Team"])
    }

    @Test func stoppingAChatLeavesItOffTheAllowList() throws {
        let rig = try Rig(container: try whatsApp(at: Date(timeIntervalSince1970: 1_790_000_000)))
        try rig.source.loadGroups()
        let chat = try #require(rig.source.groups.first)
        try rig.source.choose(chat)
        try WhatsAppSource.stopReading(chat, among: [rig.source], capture: rig.capture)
        #expect(try rig.store.currentPolicy().allowList[.whatsapp]?.contains(teamJID) != true)
        #expect(rig.source.chats.isEmpty)
    }
}

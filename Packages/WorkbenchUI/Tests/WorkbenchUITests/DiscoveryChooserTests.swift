import CaptureService
import Foundation
import Kernel
import LocalSources
import SQLite3
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The chooser over every source: the Mac's WhatsApp data and the chat open in WhatsApp Web, each chat once. Choosing is
/// the only write; stopping a chat leaves nothing of it in memory.
@MainActor @Suite struct DiscoveryChooserTests {
    private let webGroup = "123456789-1600000000@g.us"
    private let panelIDs = ["111111111@lid", "222222222@lid"]

    private struct Rig {
        let store: Store
        let capture: CaptureService
        let board = SightingBoard(descriptor: .whatsAppWeb)
        let source: WhatsAppSource

        init(container: URL) throws {
            store = try scratchStore()
            capture = try CaptureService(store: store)
            source = try WhatsAppSource(
                store: store, capture: capture, task: HelperSpec.team.task, founder: { "Kabir" }, container: container,
                web: board)
        }

        /// What the extension's host sends the app, answered by the app's own intake.
        func page(_ message: [String: Any]) -> PageHost.Reply {
            var body = message
            body["browser"] = "com.brave.Browser"
            body["url"] = "https://web.whatsapp.com/"
            let intake = WhatsAppWebIntake(
                owner: .success(try! PersonID("test-owner")), readableSources: { [] }, board: board)
            return PageHost.answer(try! JSONSerialization.data(withJSONObject: body), store: store, whatsApp: intake)
        }

        func seen(_ chat: String, title: String, members: [String: Any]? = nil) -> PageHost.Reply {
            var message: [String: Any] = ["type": "whatsapp_chat_seen", "chat": chat, "title": title]
            message["members"] = members
            return page(message)
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

    private func waitForChat(_ source: WhatsAppSource) async {
        for _ in 0..<200 where source.groups.isEmpty && source.direct.isEmpty { await Task.yield() }
    }

    private func panel(_ ids: [String]) -> [String: Any] { ["ids": ids, "rows": ids.count, "stated": ids.count] }

    // MARK: no Full Disk Access

    @Test func withNoStoreTheChatOpenInWhatsAppWebIsOfferedAndChosenAndNothingIsStoredBeforeTheChoice() async throws {
        let rig = try Rig(container: noStore)
        try rig.source.loadGroups()
        #expect(
            rig.source.groups.isEmpty && rig.source.pullProblem != nil,
            "the store cannot be read, and the person is told")
        #expect(rig.board.isOpen)

        #expect(rig.seen(webGroup, title: "Team Ops", members: panel(panelIDs)).error == nil)
        await waitForChat(rig.source)
        let offered = try #require(rig.source.groups.first)
        #expect(offered.jid == webGroup && offered.name == "Team Ops")
        #expect(rig.source.candidates.first?.seenBy == [SourceDescriptor.whatsAppWeb.key])
        #expect(rig.source.memberListHint(for: offered) == nil, "its member list is known")

        #expect(try rig.store.currentPolicy().allowList[.whatsapp] == nil, "nothing is allowed before the choice")
        #expect(try rig.count("SELECT count(*) FROM evidence") == 0)

        try rig.source.choose(offered)
        #expect(try rig.store.currentPolicy().allowList[.whatsapp] == [webGroup])
        #expect(rig.source.chats.map(\.jid) == [webGroup])
        #expect(rig.board.isOpen == false)
        #expect(
            rig.board.sightings(policy: try rig.store.currentPolicy(), now: .now).isEmpty,
            "the choice ends the question")
    }

    @Test func aChosenGroupIsWrittenWhenThePanelIsOpenAndTheChatSaysWhyWhenItIsNot() async throws {
        let rig = try Rig(container: noStore)
        try rig.source.loadGroups()
        rig.seen(webGroup, title: "Team Ops")
        await waitForChat(rig.source)
        let offered = try #require(rig.source.groups.first)
        #expect(rig.source.memberListHint(for: offered) == SourceDescriptor.whatsAppWeb.membershipHowTo)
        try rig.source.choose(offered)

        let messages: [[String: Any]] = [["id": "false_\(webGroup)_G1_111111111@lid", "text": "Send the deck Friday."]]
        let without = rig.page(["type": "whatsapp_web", "messages": messages])
        #expect(without.error == "groupAudienceUnknown")
        #expect(rig.source.waitingWords(for: offered) == SourceDescriptor.whatsAppWeb.membershipHowTo)
        #expect(try rig.count("SELECT count(*) FROM evidence") == 0)

        let with = rig.page(["type": "whatsapp_web", "messages": messages, "members": panel(panelIDs)])
        #expect(with.kept)
        #expect(rig.source.waitingWords(for: offered) == nil)
        #expect(try rig.count("SELECT count(*) FROM evidence WHERE container = '\(webGroup)'") == 1)
    }

    // MARK: merged chooser

    @Test func aChatThatTheStoreAndThePageBothSeeIsListedOnceWithBothSources() async throws {
        let rig = try Rig(container: try whatsApp(at: Date(timeIntervalSince1970: 1_790_000_000)))
        try rig.source.loadGroups()
        #expect(rig.source.groups.map(\.name) == ["Team", "Family"])
        rig.seen(teamJID, title: "Team", members: panel(["919800000011@c.us"]))
        for _ in 0..<200 where rig.source.candidates.first(where: { $0.id == teamJID })?.seenBy.count != 2 {
            await Task.yield()
        }
        #expect(rig.source.groups.map(\.name) == ["Team", "Family"], "still one entry for the team group")
        #expect(
            rig.source.candidates.first { $0.id == teamJID }?.seenBy == [
                SourceDescriptor.whatsAppChat.key, SourceDescriptor.whatsAppWeb.key,
            ])
    }

    @Test func aRuleChoosesGroupsFromEverySource() async throws {
        let rig = try Rig(container: try whatsApp(at: Date(timeIntervalSince1970: 1_790_000_000)))
        try rig.source.loadGroups()
        rig.seen(webGroup, title: "Team Ops", members: panel(panelIDs))
        for _ in 0..<200 where rig.source.groups.count < 3 { await Task.yield() }
        try rig.source.preview(ChatSelection(nameContains: "team", directWithMembers: true))
        #expect(rig.source.matching.map(\.name).sorted() == ["Team", "Team Ops"])
    }

    // MARK: stop reading

    @Test func stoppingAChatDropsItsSightingItsMembersAndItsNote() async throws {
        let rig = try Rig(container: noStore)
        try rig.source.loadGroups()
        rig.seen(webGroup, title: "Team Ops", members: panel(panelIDs))
        await waitForChat(rig.source)
        let chat = try #require(rig.source.groups.first)
        try rig.source.choose(chat)

        rig.board.open()
        rig.seen(webGroup, title: "Team Ops", members: panel(panelIDs))
        rig.board.wait(on: webGroup, words: "Open the group info.")
        let policy = try rig.store.currentPolicy()
        #expect(rig.board.sightings(policy: policy, now: .now).first?.membership?.members.count == 2)

        try WhatsAppSource.stopReading(chat, among: [rig.source], capture: rig.capture)

        #expect(rig.board.sightings(policy: policy, now: .now).isEmpty, "its members are gone from memory")
        #expect(rig.board.waiting(on: webGroup) == nil)
        #expect(try rig.store.currentPolicy().allowList[.whatsapp]?.contains(webGroup) != true)
    }
}

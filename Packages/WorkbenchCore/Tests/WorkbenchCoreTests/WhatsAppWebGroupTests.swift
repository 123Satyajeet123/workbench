import Foundation
import GRDB
import Kernel
import Lines
import Testing

@testable import WorkbenchCore

/// The WhatsApp Web page as a container source: the chat open in the page offered to the chooser, and a group written
/// only with a member list that the group-info panel proved in the same message.
@Suite struct WhatsAppWebGroupTests {
    static let group = "123456789-1600000000@g.us"
    static let policy = CapturePolicy(
        switches: [.whatsapp: true], allowList: [.whatsapp: [group, WhatsAppWebTests.chat]])
    static let sender = "111111111@lid"
    static let panelIDs = ["111111111@lid", "222222222@lid", "919800000009@c.us"]

    static var groupMessages: [[String: Any]] {
        [
            WhatsAppWebTests.message(
                "false_\(group)_G1_\(sender)", "Send the deck Friday.", sent: "3:45 PM, 11/22/2026"),
            WhatsAppWebTests.message("true_\(group)_G2", "I will review it Monday.", sent: "3:50 PM, 11/22/2026"),
        ]
    }

    static func panel(ids: [String] = panelIDs, rows: Int? = nil, stated: Int? = panelIDs.count) -> [String: Any] {
        var panel: [String: Any] = ["ids": ids, "rows": rows ?? ids.count]
        if let stated { panel["stated"] = stated }
        return panel
    }

    static func snapshot(_ messages: [[String: Any]], members: [String: Any]?) throws -> Data {
        var body: [String: Any] = [
            "type": "whatsapp_web", "browser": "com.brave.Browser", "url": "https://web.whatsapp.com/",
            "messages": messages,
        ]
        body["members"] = members
        return try JSONSerialization.data(withJSONObject: body)
    }

    static func seen(
        chat: String, title: String = "Team Ops", members: [String: Any]? = nil,
        url: String = "https://web.whatsapp.com/"
    ) throws -> Data {
        var body: [String: Any] = [
            "type": "whatsapp_chat_seen", "browser": "com.brave.Browser", "url": url, "chat": chat, "title": title,
        ]
        body["members"] = members
        return try JSONSerialization.data(withJSONObject: body)
    }

    private struct Rig {
        let store: Store
        let board = SightingBoard(descriptor: .whatsAppWeb)
        let intake: WhatsAppWebIntake

        init(policy: CapturePolicy = WhatsAppWebGroupTests.policy) throws {
            store = try EvidenceIngestTests.World(allowing: []).store
            try store.savePolicy(policy)
            intake = WhatsAppWebIntake(
                owner: .success(try PersonID("test-owner")), readableSources: { [] }, board: board,
                zone: WhatsAppWebTests.zone)
        }

        func answer(_ data: Data) -> PageHost.Reply { PageHost.answer(data, store: store, whatsApp: intake) }

        func lines() throws -> [Row] {
            try store.writer.read {
                try Row.fetchAll(
                    $0, sql: "SELECT text, actor, container, hex(audience_digest) AS digest FROM evidence ORDER BY id")
            }
        }

        var sightings: [ContainerSighting] { board.sightings(policy: WhatsAppWebGroupTests.policy, now: store.clock()) }
    }

    // MARK: discovery

    @Test func theStatusSaysWhetherTheChooserIsOpenAndNamesAllowedGroupsToo() throws {
        let rig = try Rig()
        #expect(rig.answer(WhatsAppWebTests.status()).discover == false)
        rig.board.open()
        let reply = rig.answer(WhatsAppWebTests.status())
        #expect(reply.discover == true)
        #expect(reply.chats == [WhatsAppWebTests.chat, Self.group].sorted(), "a group is read when allowed")
        rig.board.close()
        #expect(rig.answer(WhatsAppWebTests.status()).discover == false)
    }

    @Test func theOpenChatIsTakenOnlyWhileTheChooserIsOpen() throws {
        let rig = try Rig()
        let closed = rig.answer(
            try Self.seen(chat: WhatsAppWebTests.chat.replacingOccurrences(of: "s.whatsapp.net", with: "c.us")))
        #expect(closed.error == "chooserClosed")
        #expect(rig.sightings.isEmpty)

        rig.board.open()
        let reply = rig.answer(try Self.seen(chat: "919800000001@c.us", title: " Ana Rao "))
        #expect(reply.error == nil)
        let seen = try #require(rig.sightings.first)
        #expect(seen.container == Container(id: WhatsAppWebTests.chat, kind: .direct, title: "Ana Rao"))
        #expect(seen.source == SourceDescriptor.whatsAppWeb.key && seen.membership == nil)
    }

    @Test func aSightingOfAnUnchosenChatLeavesTheStoreAndThePolicyAsTheyWere() throws {
        let rig = try Rig(policy: CapturePolicy(switches: [.whatsapp: true]))
        rig.board.open()
        let before = try rig.store.currentPolicy()
        _ = rig.answer(try Self.seen(chat: Self.group, members: Self.panel()))
        #expect(rig.sightings.count == 1)
        #expect(try rig.store.currentPolicy() == before)
        #expect(try rig.lines().isEmpty)
        #expect(try rig.store.writer.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM state") } == 0)
    }

    @Test func aSightingFromAnotherPageOrWithABadChatOrTitleIsRefused() throws {
        let rig = try Rig()
        rig.board.open()
        #expect(rig.answer(try Self.seen(chat: Self.group, url: "https://evil.example/")).error == "notWhatsAppWeb")
        #expect(rig.answer(try Self.seen(chat: "Ana Rao")).error == "unrecognizedChat")
        #expect(rig.answer(try Self.seen(chat: Self.group, title: "  ")).error == "unusableTitle")
        #expect(
            rig.answer(try Self.seen(chat: Self.group, title: String(repeating: "x", count: 201))).error
                == "unusableTitle")
        #expect(rig.sightings.isEmpty)
    }

    // MARK: membership

    @Test func aGroupSightingCarriesTheMembersOnlyWhenEveryRowGaveAnId() throws {
        let rig = try Rig()
        rig.board.open()
        _ = rig.answer(try Self.seen(chat: Self.group, members: Self.panel()))
        let whole = try #require(rig.sightings.first?.membership)
        #expect(whole.members == ["111111111@lid", "222222222@lid", "919800000009@s.whatsapp.net"])
        #expect(whole.proof == .infoPanel)

        _ = rig.answer(try Self.seen(chat: Self.group, members: Self.panel(ids: ["111111111@lid"], rows: 3)))
        #expect(rig.sightings.first?.membership == nil, "one row gave an id and two did not")
    }

    @Test(arguments: [
        #"{"ids":["Ana Rao","Bharat K"],"rows":2,"stated":2}"#,
        #"{"ids":["+91 98000 00001","+91 98000 00002"],"rows":2,"stated":2}"#,
        #"{"ids":["919800000001","919800000002"],"rows":2,"stated":2}"#,
        #"{"ids":["Ana@lid","222222222@lid"],"rows":2,"stated":2}"#,
        #"{"ids":["111111111@lid","222222222@lid"],"rows":2}"#,
        #"{"ids":["111111111@lid","222222222@lid"],"rows":2,"stated":5}"#,
        #"{"ids":["111111111@lid","111111111@lid"],"rows":2,"stated":2}"#,
        #"{"ids":[],"rows":0,"stated":0}"#,
    ])
    func aNameANumberAsShownOrAGappedListNeverBecomesAMembership(panel: String) throws {
        #expect(try JSONDecoder().decode(WebPanel.self, from: Data(panel.utf8)).membership() == nil)
    }

    @Test func aGroupIsWrittenWithTheAudienceOfAPanelThatProvedItsMembers() throws {
        let rig = try Rig()
        let reply = rig.answer(try Self.snapshot(Self.groupMessages, members: Self.panel()))
        #expect(reply == PageHost.Reply(kept: true))
        let rows = try rig.lines()
        #expect(rows.map { $0["text"] as String } == ["Send the deck Friday.", "I will review it Monday."])
        #expect(rows.map { $0["actor"] as String } == ["111111111@lid", "me"])
        let expected = AudienceDigest(
            owner: "me", members: ["111111111@lid", "222222222@lid", "919800000009@s.whatsapp.net"])
        #expect(
            rows.map { $0["digest"] as String }
                == Array(repeating: Data(expected.bytes).map { String(format: "%02X", $0) }.joined(), count: 2))
        #expect(
            try rig.store.writer.read {
                try Int.fetchOne($0, sql: "SELECT count(DISTINCT entity_key) FROM evidence")
            } == 2)
    }

    @Test func aGroupIsRefusedWithoutAPanelAndTheBoardSaysWhatThePersonCanDo() throws {
        let rig = try Rig()
        let reply = rig.answer(try Self.snapshot(Self.groupMessages, members: nil))
        #expect(reply.kept == false && reply.error == "groupAudienceUnknown")
        #expect(try rig.lines().isEmpty)
        let words = try #require(rig.board.waiting(on: Self.group))
        #expect(
            words == "Open the group info in WhatsApp Web while this group is open, so Workbench can see who is in it.")

        #expect(rig.answer(try Self.snapshot(Self.groupMessages, members: Self.panel())).kept)
        #expect(rig.board.waiting(on: Self.group) == nil, "the note goes when the group is read")
    }

    @Test func aPanelWithNamesInsteadOfIdsLeavesTheGroupUnwritten() throws {
        let rig = try Rig()
        let names = Self.panel(ids: ["Ana Rao", "Bharat K", "+91 98000 00009"], stated: 3)
        let reply = rig.answer(try Self.snapshot(Self.groupMessages, members: names))
        #expect(reply.error == "groupAudienceUnknown")
        #expect(try rig.lines().isEmpty)
        #expect(rig.board.waiting(on: Self.group) != nil)
    }

    @Test func aPanelThatIsNotWholeLeavesTheGroupUnwritten() throws {
        let rig = try Rig()
        for panel in [
            Self.panel(ids: ["111111111@lid"], rows: 3), Self.panel(stated: 7), Self.panel(stated: nil),
        ] {
            #expect(rig.answer(try Self.snapshot(Self.groupMessages, members: panel)).error == "groupAudienceUnknown")
        }
        #expect(try rig.lines().isEmpty)
    }

    @Test func aGroupMessageFromAnotherAccountNeedsItsSenderToBeKeyed() throws {
        let rig = try Rig()
        let nameless = [WhatsAppWebTests.message("false_\(Self.group)_G1", "Who sent this?")]
        let reply = rig.answer(try Self.snapshot(nameless, members: Self.panel()))
        #expect(reply.error == "senderUnknown")
        #expect(try rig.lines().isEmpty)
    }

    @Test func aDirectChatNeedsNoPanel() throws {
        let rig = try Rig()
        let page = try Self.snapshot([WhatsAppWebTests.first], members: nil)
        #expect(rig.answer(page).kept)
    }

    @Test func aGroupThePersonDidNotChooseIsNeverWrittenWhateverThePanelSays() throws {
        let rig = try Rig(
            policy: CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [WhatsAppWebTests.chat]]))
        let reply = rig.answer(try Self.snapshot(Self.groupMessages, members: Self.panel()))
        #expect(reply.error == "chatNotAllowed")
        #expect(try rig.lines().isEmpty)
        #expect(rig.board.waiting(on: Self.group) == nil, "an unchosen group leaves no note")
    }
}

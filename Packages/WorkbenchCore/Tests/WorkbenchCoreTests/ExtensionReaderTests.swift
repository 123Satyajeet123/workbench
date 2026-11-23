import Foundation
import Testing

@testable import WorkbenchCore

/// Runs the extension's Gmail reading and deck code in a headless Chromium against a saved fixture. The fixture was
/// written to match the Gmail structure in `Extension/mail/selectors.js`; it is UNVERIFIED against a live Gmail tab.
/// The run uses a throwaway browser profile and opens no network page.
@Suite(.enabled(if: Chromium.binary != nil, "needs a Chromium: a Playwright headless shell, Chrome or Brave"))
struct ExtensionReaderTests {
    private func run(fixture: String, harnessName: String = "harness.html") throws -> [String: Any] {
        let root = NoEgressTests.repo
        let scratch = temporaryDirectory()
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let harness = try String(contentsOf: root.appending(path: "ExtensionTests/\(harnessName)"), encoding: .utf8)
        let body = try String(contentsOf: root.appending(path: "ExtensionTests/fixtures/\(fixture)"), encoding: .utf8)
        let page = scratch.appending(path: "page.html")
        try harness.replacingOccurrences(of: "{{ROOT}}", with: root.path)
            .replacingOccurrences(of: "<!--FIXTURE-->", with: body).write(to: page, atomically: true, encoding: .utf8)
        let dom = try Chromium.dump(page, profile: scratch.appending(path: "profile"))
        let encoded = try #require(dom.firstMatch(of: #/data-out="([^"]+)"/#)?.1, "the harness wrote no result")
        let json = try #require(Data(base64Encoded: String(encoded)))
        return try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
    }

    @Test func theReaderFindsTheExpandedMessagesTheirSendersAndThePdfAttachment() throws {
        let out = try run(fixture: "thread-with-deck.html")
        let thread = try #require(out["thread"] as? [String: Any])
        #expect(thread["label"] as? String == "Deals" && thread["threadId"] as? String == "FMfcgzQ")
        #expect(thread["subject"] as? String == "Acme: seed round, deck attached")
        let messages = try #require(thread["messages"] as? [[String: Any]])
        #expect(
            messages.map { $0["messageId"] as? String } == ["msg-f:1801000000000000001", "msg-f:1801000000000000003"],
            "the collapsed message has no body and is left out")
        try #require(messages.count == 2)
        #expect(messages[0]["sender"] as? String == "Ana Rao <ana@acme.example>")
        #expect(messages[1]["sender"] as? String == "raj@acme.example")
        let text = try #require(messages[0]["text"] as? String)
        #expect(text.contains("We are raising a 2M seed round.") && text.contains("Hi,"))
        #expect(messages[0]["sent"] as? Int == out["dateInTitle"] as? Int)
        #expect(messages[1]["sent"] is NSNull, "a date that does not parse is null, not a guess")
        let attachments = try #require(messages[0]["attachments"] as? [[String: String]])
        #expect(attachments.count == 1, "the picture is not a deck")
        #expect(attachments[0]["name"] == "Acme Seed Deck.pdf")
        #expect(attachments[0]["url"]?.hasPrefix("https://mail.google.com/mail/u/0?ui=2&ik=abc123&attid=0.1") == true)
        #expect((messages[1]["attachments"] as? [Any])?.isEmpty == true)
    }

    @Test func onlyAThreadOpenInsideALabelIsRead() throws {
        let out = try run(fixture: "thread-with-deck.html")
        let hashes = try #require(out["hashes"] as? [String: Any])
        func place(_ hash: String) -> [String: String]? { hashes[hash] as? [String: String] }
        #expect(place("#label/Deals/FMfcgzQ") == ["label": "Deals", "threadId": "FMfcgzQ"])
        #expect(place("#label/Hot+Deals/FMfcgzQ")?["label"] == "Hot Deals")
        #expect(place("#label/Parent%2FChild/FMfcgzQ")?["label"] == "Parent/Child")
        #expect(place("#label/Deals/FMfcgzQ?compose=new")?["threadId"] == "FMfcgzQ")
        for hash in [
            "#inbox", "#label/Deals", "#search/acme/FMfcgzQ", "#label/Deals/not%20an%20id", "", "#label//FMfcgzQ",
        ] {
            #expect(place(hash) == nil, "\(hash) is not a thread in a label")
        }
        #expect((out["noThreadOutsideALabel"] as? [Any])?.allSatisfy { $0 is NSNull } == true)
    }

    @Test func theDeckFetchStaysOnTheGmailOriginAndWithinItsLimits() throws {
        let out = try run(fixture: "thread-with-deck.html")
        let sameOrigin = try #require(out["sameOrigin"] as? [String: Bool])
        let allowed = sameOrigin.filter(\.value).keys.sorted()
        #expect(allowed == ["/mail/u/0?ui=2&view=att", "https://mail.google.com/mail/u/0?ui=2&view=att"])

        #expect(out["fetched"] as? [Int] == [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37, 0x0a, 1, 2, 3])
        let options = try #require(out["fetchOptions"] as? [String: String])
        #expect(options["credentials"] == "same-origin" && options["redirect"] == "error")
        #expect(options["address"] == "https://mail.google.com/mail/u/0?ui=2&view=att")
        #expect((out["foreign"] as? [Any])?.allSatisfy { $0 is NSNull } == true)
        #expect(out["callsForForeign"] as? Int == 0, "a foreign address is never requested")
        for refused in ["notAPdf", "tooBig", "refused", "redirected"] {
            #expect(out[refused] is NSNull, "\(refused) gives no deck")
        }
        let fetches = try #require(out["rateWithinAnHour"] as? [Bool])
        #expect(out["fetchesInTheHour"] as? Int == 20, "no more than 20 requests an hour")
        #expect(fetches.filter { $0 }.count == 15, "5 requests were made before the loop, so 15 more pass")
        #expect(out["allowedAfterTheHour"] as? Bool == true)
    }

    @Test func whatsAppReadsOneVerifiedChatAndShowsDeletedMessagesWithinItsLimits() throws {
        let out = try run(fixture: "whatsapp-open-chat.html", harnessName: "whatsapp-harness.html")
        let read = try #require(out["read"] as? [String: Any])
        #expect(read["status"] as? String == "read" && read["chatId"] as? String == "919800000001@c.us")
        #expect(read["truncated"] as? Bool == false)
        let messages = try #require(read["messages"] as? [[String: Any]])
        #expect(
            messages.map { $0["id"] as? String } == [
                "false_919800000001@c.us_FIRST", "true_919800000001@c.us_SECOND", "false_919800000001@c.us_GONE",
            ], "the repeated row, the hidden row, the other chat and the unsent draft are left out")
        #expect(messages.map { $0["text"] as? String } == ["Send the deck Friday.", "I will review it Monday.", nil])
        #expect(messages.map { $0["deleted"] as? Bool } == [nil, nil, true])
        #expect(messages.map { $0["sent"] as? String } == ["3:45 PM, 11/22/2026", "3:50 PM, 11/22/2026", nil])
        #expect((out["replay"] as? [String: Any])?["messages"] as? [[String: Any]] != nil)

        let bounded = try #require(out["bounded"] as? [String: Any])
        #expect(bounded["truncated"] as? Bool == true, "20,001 characters do not fit")
        #expect((bounded["messages"] as? [[String: Any]])?.count == 3, "the newest messages stay")
        let many = try #require(out["many"] as? [String: Any])
        #expect(many["truncated"] as? Bool == true && many["count"] as? Int == 200)
        #expect(many["last"] as? String == "false_919800000001@c.us_BULK204", "the newest 200 stay")
        for (key, status) in [
            ("mixed", "unverified-chat"), ("unrecognized", "unverified-chat"), ("empty", "unverified-chat"),
            ("noChat", "no-open-chat"),
        ] {
            #expect((out[key] as? [String: Any])?["status"] as? String == status, "\(key)")
        }
        #expect(
            out["canonical"] as? [String] == [
                "919800000001@s.whatsapp.net", "919800000001@s.whatsapp.net", "123@g.us", "77@lid",
            ])
    }

    @Test func whatWhatsAppReadsReachesTheStoreAsLinesAndAGroupReachesNothing() throws {
        let out = try run(fixture: "whatsapp-open-chat.html", harnessName: "whatsapp-harness.html")
        let world = try EvidenceIngestTests.World(allowing: [])
        let chat = "919800000001@s.whatsapp.net"
        try world.store.savePolicy(
            CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [chat, "123456789-1600000000@g.us"]]))
        func send(_ reading: Any?) throws -> PageHost.Reply {
            var payload = try #require(reading as? [String: Any])
            payload["type"] = "whatsapp_web"
            payload["browser"] = "com.brave.Browser"
            payload["url"] = "https://web.whatsapp.com/"
            return PageHost.answer(
                try JSONSerialization.data(withJSONObject: payload), store: world.store,
                whatsApp: WhatsAppWebTests.intake())
        }
        #expect(try send(out["read"]) == PageHost.Reply(kept: true))
        let stored = try world.store.writer.read {
            try String.fetchAll($0, sql: "SELECT text || tombstone FROM evidence ORDER BY id")
        }
        #expect(stored == ["Send the deck Friday.0", "I will review it Monday.0", "1"])
        #expect(try send(out["read"]) == PageHost.Reply(kept: false), "a second reading adds nothing")
        #expect(try send(out["group"]).error == "groupAudienceUnknown")
        #expect(try world.count("SELECT count(*) FROM evidence") == 3)
    }

    // MARK: group-info panel and probe

    private func panelRun() throws -> [String: Any] {
        try run(fixture: "whatsapp-group-open.html", harnessName: "whatsapp-panel-harness.html")
    }

    private func panel(_ value: Any?) throws -> WebPanel {
        try JSONDecoder().decode(
            WebPanel.self, from: JSONSerialization.data(withJSONObject: try #require(value as? [String: Any])))
    }

    @Test func theGroupInfoPanelGivesMembersOnlyFromAttributesThatHoldAnIdAndOnlyWhenWhole() throws {
        let out = try panelRun()
        let identity = try #require(out["identity"] as? [String: Any])
        #expect(identity["status"] as? String == "read" && identity["chatId"] as? String == "123456789-1600000000@g.us")
        #expect(identity["title"] as? String == "Team Ops")
        let whole = try panel(identity["members"])
        #expect(
            whole.ids == ["111111111@lid", "919800000002@c.us", "222222222@lid"], "ids from attributes, in row order")
        #expect(whole.rows == 3 && whole.stated == 3)
        #expect(whole.membership()?.members.count == 3)
        #expect((out["read"] as? [String: Any])?["members"] as? [String: Any] != nil, "a reading carries the same list")

        let gap = try panel(out["gap"])
        #expect(gap.ids.count == 2 && gap.rows == 3 && gap.membership() == nil, "a row with no id leaves a gap")
        let names = try panel(out["namesOnly"])
        #expect(names.ids.isEmpty && names.rows == 3 && names.membership() == nil, "names give no ids")
        let text = try panel(out["textIsNotAnId"])
        #expect(text.ids.count == 2 && text.membership() == nil, "an id written as text is not read")
        #expect(try panel(out["noStatedCount"]).membership() == nil, "no stated count, no proof")
        #expect(out["otherChatsPanel"] is NSNull, "a panel with another title is not this chat's")
        #expect(out["noPanel"] is NSNull)
    }

    @Test func theChatIdentityHoldsAnIdATitleAndMembersAndNoMessage() throws {
        let out = try panelRun()
        let identity = try #require(out["identity"] as? [String: Any])
        #expect(Set(identity.keys) == ["status", "chatId", "title", "members"])
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: identity), as: UTF8.self)
        #expect(!encoded.contains("Send the deck") && !encoded.contains("Monday"))
        let direct = try #require(out["direct"] as? [String: Any])
        #expect(direct["chatId"] as? String == "919800000002@c.us" && direct["title"] as? String == "Bharat")
        #expect(direct["members"] is NSNull, "a direct chat has no panel list")
        #expect((out["noMessages"] as? [String: Any])?["status"] as? String == "unverified-chat")
    }

    @Test func theProbeReturnsStructureAndNoNameNumberIdOrText() throws {
        let probe = try #require(try panelRun()["probe"] as? [String: Any])
        let json = String(decoding: try JSONSerialization.data(withJSONObject: probe), as: UTF8.self)
        let planted = [
            "Ana", "Rao", "Bharat", "98000", "919800", "111111111", "222222222", "123456789", "Team Ops",
            "Send the deck",
            "Monday", "@", "participants", "9198765432",
        ]
        for token in planted { #expect(!json.contains(token), "the probe output holds \(token)") }
        #expect(json.firstMatch(of: #/\d{4,}/#) == nil, "no long number")
        for found in [
            "phone-shaped jid", "lid", "message id with lid sender", "message id with no sender", "data-jid", "data-x",
        ] {
            #expect(json.contains(found), "the probe did not report \(found)")
        }
        #expect(json.contains("(odd name)"), "a name that holds a number is reported as odd, not as itself")
        #expect(json.utf8.count < 20_000)
    }

    @Test func aLargeDeckIsCutIntoChunksThatJoinBack() throws {
        let out = try run(fixture: "thread-with-deck.html")
        #expect(out["chunkCount"] as? Int == 3, "1.2 MB in chunks of 512 KiB")
        #expect(out["chunksRoundTrip"] as? Bool == true)
        #expect(out["smallestChunk"] as? Int == 0)
    }
}

/// A Chromium found on this Mac, driven only to print a page's DOM.
enum Chromium {
    static let binary: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cache = home.appending(path: "Library/Caches/ms-playwright")
        let shells = ((try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? [])
            .filter { $0.hasPrefix("chromium_headless_shell-") }.sorted().reversed()
            .map { cache.appending(path: "\($0)/chrome-headless-shell-mac-arm64/chrome-headless-shell") }
        let apps = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
        ].map { URL(filePath: $0) }
        return (shells + apps).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }()

    /// The page's DOM after its scripts ran, from a browser with a throwaway profile.
    static func dump(_ page: URL, profile: URL) throws -> String {
        let process = Process()
        process.executableURL = binary
        process.arguments = [
            "--headless=new", "--disable-gpu", "--no-sandbox", "--user-data-dir=\(profile.path)",
            "--allow-file-access-from-files", "--virtual-time-budget=8000", "--dump-dom", page.absoluteString,
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

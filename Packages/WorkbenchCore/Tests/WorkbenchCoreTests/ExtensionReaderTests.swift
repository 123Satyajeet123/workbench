import Foundation
import Testing

@Suite(.enabled(if: Chromium.binary != nil, "needs a Chromium: a Playwright headless shell, Chrome or Brave"))
struct ExtensionReaderTests {
    private func run(fixture: String) throws -> [String: Any] {
        let root = NoEgressTests.repo
        let scratch = temporaryDirectory()
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let harness = try String(contentsOf: root.appending(path: "ExtensionTests/harness.html"), encoding: .utf8)
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

    @Test func aLargeDeckIsCutIntoChunksThatJoinBack() throws {
        let out = try run(fixture: "thread-with-deck.html")
        #expect(out["chunkCount"] as? Int == 3, "1.2 MB in chunks of 512 KiB")
        #expect(out["chunksRoundTrip"] as? Bool == true)
        #expect(out["smallestChunk"] as? Int == 0)
    }
}

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

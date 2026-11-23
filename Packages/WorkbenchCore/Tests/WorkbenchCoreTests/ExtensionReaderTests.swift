import Foundation
import Testing

@testable import WorkbenchCore

/// Runs the extension's reading code in a headless Chromium against saved fixtures. The fixtures were written to match
/// the structure that research 64 measured and the attributes the adapter records name; they are UNVERIFIED against
/// live pages. The run uses a throwaway browser profile and opens no network page.
enum ExtensionHarness {
    static func run(fixture: String, attribute: String = "data-out") throws -> [String: Any] {
        let root = NoEgressTests.repo
        let scratch = temporaryDirectory()
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let harness = try String(contentsOf: root.appending(path: "ExtensionTests/harness.html"), encoding: .utf8)
        let body = try String(contentsOf: root.appending(path: "ExtensionTests/fixtures/\(fixture)"), encoding: .utf8)
        let page = scratch.appending(path: "page.html")
        try harness.replacingOccurrences(of: "{{ROOT}}", with: root.path)
            .replacingOccurrences(of: "<!--FIXTURE-->", with: body).write(to: page, atomically: true, encoding: .utf8)
        let dom = try Chromium.dump(page, profile: scratch.appending(path: "profile"))
        let encoded = try #require(
            dom.firstMatch(of: try Regex("\(attribute)=\"([^\"]+)\""))?.output[1].substring,
            "the harness wrote no \(attribute)")
        let json = try #require(Data(base64Encoded: String(encoded)))
        return try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
    }

    /// Whether two parsed JSON values are equal.
    static func same(_ left: Any?, _ right: Any?) -> Bool {
        guard let left = left as? NSObject, let right = right as? NSObject else { return false }
        return left.isEqual(right)
    }
}

@Suite(.enabled(if: Chromium.binary != nil, "needs a Chromium: a Playwright headless shell, Chrome or Brave"))
struct ExtensionReaderTests {
    private func run(fixture: String) throws -> [String: Any] { try ExtensionHarness.run(fixture: fixture) }

    private func messages(of thread: Any?) throws -> [[String: Any]] {
        try #require((thread as? [String: Any])?["messages"] as? [[String: Any]])
    }

    @Test func theReaderFindsTheExpandedMessagesTheirSendersAndThePdfAttachment() throws {
        let out = try run(fixture: "gmail-thread.html")
        let thread = try #require(out["thread"] as? [String: Any])
        #expect(thread["label"] as? String == "Deals")
        #expect(thread["threadId"] as? String == "thread-f:1801000000000000000")
        #expect(thread["threadVia"] as? String == "data-thread-id")
        let messages = try messages(of: thread)
        #expect(
            messages.map { $0["messageId"] as? String } == ["msg-f:1801000000000000001", "msg-f:1801000000000000003"],
            "the collapsed message has no body and is left out")
        try #require(messages.count == 2)
        #expect(messages[0]["sender"] as? String == "ana@acme.example")
        #expect(messages[1]["sender"] as? String == "raj@acme.example")
        let text = try #require(messages[0]["text"] as? String)
        #expect(text.contains("We are raising a 2M seed round.") && text.contains("Hi,"))
        #expect(!text.contains("please send"), "the quoted block is not the sender's own words")
        #expect(messages[0]["quoted"] as? String == "On Thu: please send")
        #expect(messages[1]["quoted"] as? String == "", "a message with no quoted block has none")
        #expect(messages[0]["sent"] as? Int == out["dateInTitle"] as? Int)
        #expect(messages[1]["sent"] is NSNull, "a date that does not parse is null, not a guess")
        let attachments = try #require(messages[0]["attachments"] as? [[String: String]])
        #expect(attachments.count == 1, "the picture is not a deck")
        #expect(attachments[0]["name"] == "Acme Seed Deck.pdf")
        #expect(attachments[0]["url"]?.hasPrefix("https://mail.google.com/mail/u/0?ui=2&ik=abc123&attid=0.1") == true)
        #expect((messages[1]["attachments"] as? [Any])?.isEmpty == true)
    }

    @Test func theHeaderAddressesComeFromAttributesAndAreEmptyWhenThePageShowsNoRecipient() throws {
        let out = try run(fixture: "gmail-thread.html")
        let read = try messages(of: out["thread"])
        #expect(read[0]["recipients"] as? [String] == ["vc@fund.example", "Raj@Acme.example"])
        #expect(
            (read[1]["recipients"] as? [String])?.isEmpty == true,
            "the second message shows its sender and no recipient: 1 of 2 read messages has none")
        #expect(read.allSatisfy { $0["account"] as? String == "vc@fund.example" })
        let noAccount = try messages(of: out["threadWithoutAccount"])
        #expect(noAccount.allSatisfy { $0["account"] is NSNull }, "no account label, no account: nothing is guessed")
        let noAttributes = try messages(of: out["threadWithoutAddressAttributes"])
        #expect(noAttributes.allSatisfy { ($0["sender"] as? String)?.isEmpty == true })
    }

    @Test func aQuotedBlockIsMarkedByItsTagNeverByItsWords() throws {
        let out = try run(fixture: "gmail-thread.html")
        let untagged = try messages(of: out["threadWithoutQuoteTag"])
        #expect(untagged[0]["quoted"] as? String == "", "the same words in a plain block are the sender's words")
        #expect((untagged[0]["text"] as? String)?.contains("please send") == true)
    }

    @Test func theThreadIdFallsBackFromTheNamedAttributesToTheAddress() throws {
        let out = try run(fixture: "gmail-thread.html")
        let legacy = try #require(out["threadWithoutThreadId"] as? [String: Any])
        #expect(legacy["threadId"] as? String == "18c0a1b2c3d4e5f6")
        #expect(legacy["threadVia"] as? String == "data-legacy-thread-id")
        let address = try #require(out["threadFromTheAddress"] as? [String: Any])
        #expect(address["threadId"] as? String == "FMfcgzQ" && address["threadVia"] as? String == "url")
    }

    @Test func aMessageWhoseIdCannotBeReadIsKeptWithoutAnIdNeverGivenAMadeUpOne() throws {
        let out = try run(fixture: "gmail-thread.html")
        let thread = try messages(of: out["threadWithOneUnnamedMessage"])
        #expect(thread.map { $0["messageId"] as? String } == ["msg-f:1801000000000000003"])
        let page = try #require(out["pageWithOneUnnamedMessage"] as? [String: Any])
        let items = try #require(page["items"] as? [[String: Any]])
        #expect(items.map { $0["id"] as? String } == [nil, "msg-f:1801000000000000002", "msg-f:1801000000000000003"])
        #expect(items[0]["via"] is NSNull, "no source gave the first message an id")
        #expect((items[0]["text"] as? String)?.isEmpty == false, "its words are still read, as a line with no id")
    }

    @Test func onlyAThreadOpenInsideALabelIsRead() throws {
        let out = try run(fixture: "gmail-thread.html")
        let labels = try #require(out["labels"] as? [String: Any])
        #expect(labels["#label/Deals/FMfcgzQ"] as? String == "Deals")
        #expect(labels["#label/Hot+Deals/FMfcgzQ"] as? String == "Hot Deals")
        #expect(labels["#label/Parent%2FChild/FMfcgzQ"] as? String == "Parent/Child")
        #expect(labels["#label/Deals/FMfcgzQ?compose=new"] as? String == "Deals")
        for hash in [
            "#inbox", "#label/Deals", "#search/acme/FMfcgzQ", "#label/Deals/not%20an%20id", "", "#label//FMfcgzQ",
        ] {
            #expect(labels[hash] is NSNull, "\(hash) is not a thread in a label")
        }
        #expect((out["noThreadOutsideALabel"] as? [Any])?.allSatisfy { $0 is NSNull } == true)
    }

    @Test func aGmailPageThatLostItsMessageAttributesIsStaleAndReadsNothing() throws {
        let out = try run(fixture: "gmail-thread.html")
        #expect(
            ExtensionHarness.same(out["threadWithoutMessageIds"], ["stale": "Gmail"]),
            "no thread, and the name of the site to report")
        let page = try #require(out["pageWithoutItemAttributes"] as? [String: Any])
        #expect(ExtensionHarness.same(page["shape"], ["site": "Gmail", "stale": true]))
        #expect((page["items"] as? [Any])?.isEmpty == true, "a stale adapter gives no lines")
        #expect(page["container"] is NSNull)
        let shown = try #require(out["page"] as? [String: Any])
        #expect(ExtensionHarness.same(shown["shape"], ["site": "Gmail", "stale": false]))
        #expect((shown["items"] as? [Any])?.count == 3, "with its attributes the page reads")
    }

    @Test func theReaderDoesNotNeedClassNames() throws {
        for fixture in ["gmail-thread.html", "slack-channel.html", "feed-no-record.html"] {
            let out = try run(fixture: fixture)
            #expect(ExtensionHarness.same(out["page"], out["pageWithoutClasses"]), "\(fixture): the page")
            if fixture.hasPrefix("gmail") {
                #expect(ExtensionHarness.same(out["thread"], out["threadWithoutClasses"]), "the thread")
            }
        }
    }

    @Test func theInterpreterRefusesToSelectByClass() throws {
        let out = try run(fixture: "gmail-thread.html")
        let counts = try #require(out["itemsNamedByAttribute"] as? [String: Int])
        #expect(counts["data-message-id"] == 3, "a named attribute finds the three messages")
        #expect(counts["class"] == 0 && counts["[class]"] == 0 && counts["data-message-id]"] == 0)
    }

    @Test func slackMessagesGetTheirIdFromTheRowAndTheirChannelFromTheAddress() throws {
        let out = try run(fixture: "slack-channel.html")
        let page = try #require(out["page"] as? [String: Any])
        #expect(ExtensionHarness.same(page["container"], ["value": "T0123456789/C0123456789", "via": "url"]))
        let items = try #require(page["items"] as? [[String: Any]])
        #expect(items.map { $0["id"] as? String } == ["1700000000.000100", "1700000060.000200"])
        #expect(items.allSatisfy { $0["via"] as? String == "id" })
        #expect((items[0]["text"] as? String)?.contains("Term sheet is signed.") == true)
        #expect(ExtensionHarness.same(page["shape"], ["site": "Slack", "stale": false]))
        #expect(
            (page["text"] as? String)?.contains("a draft the person is typing") == false,
            "a typed draft is never read")
    }

    @Test func aSlackPageThatLostItsRowIdsIsStaleButItsTextIsStillRead() throws {
        let out = try run(fixture: "slack-channel.html")
        let page = try #require(out["pageWithoutItemAttributes"] as? [String: Any])
        #expect(ExtensionHarness.same(page["shape"], ["site": "Slack", "stale": true]))
        #expect((page["items"] as? [Any])?.isEmpty == true)
        #expect((page["text"] as? String)?.contains("Term sheet is signed.") == true, "the generic text layer works")
    }

    @Test func aSiteWithNoRecordGivesLinesWithNoIdAndNoContainer() throws {
        let out = try run(fixture: "feed-no-record.html")
        let page = try #require(out["page"] as? [String: Any])
        #expect(page["shape"] is NSNull && page["container"] is NSNull)
        let items = try #require(page["items"] as? [[String: Any]])
        #expect(items.count == 6)
        #expect(items.allSatisfy { $0["id"] is NSNull && $0["via"] is NSNull }, "no id is made up")
        #expect(items.compactMap { $0["text"] as? String }.joined().contains("Raised a seed round of 2M."))
    }

    @Test func theGenericReaderUsesAriaRolesNotClassNames() throws {
        let out = try run(fixture: "feed-no-record.html")
        let blocks = try #require(out["blocks"] as? [[String: String]])
        #expect(blocks.map { $0["role"] } == ["heading", "listitem", "listitem", "row", "article", "text"])
        #expect(blocks[1]["text"] == "Maya Iyer\nRaised a seed round of 2M.")
        #expect(blocks[5]["text"] == "Loose text with a misleading name.", "a class named like a role gives no role")
    }

    @Test func theGenericReaderReadsOnlyWhatIsOnScreenAndNeverATypedField() throws {
        let out = try run(fixture: "feed-no-record.html")
        let seen = try #require(out["blocks"] as? [[String: String]]).compactMap { $0["text"] }
            .joined(separator: "\n")
        #expect(!seen.contains("Far below the screen") && !seen.contains("Hidden text"))
        #expect(!seen.contains("typed secret") && !seen.contains("draft in an editor"))
        let all = try #require(out["blocksWithoutAView"] as? [[String: String]]).compactMap { $0["text"] }
            .joined(separator: "\n")
        #expect(all.contains("Far below the screen"), "without a view, text off the screen is read")
        #expect(!all.contains("Hidden text") && !all.contains("typed secret") && !all.contains("draft in an editor"))
    }

    @Test func eachFrameIsReadFromItsOwnDocument() throws {
        let out = try run(fixture: "frames.html")
        let frames = try #require(out["frames"] as? [String: String])
        #expect(frames["top"] == "Top frame text.", "the top document does not include its frame's text")
        #expect(frames["inner"] == "Text inside the frame.", "the frame's own script reads it")
    }

    @Test func theDeckFetchStaysOnTheGmailOriginAndWithinItsLimits() throws {
        let out = try run(fixture: "gmail-thread.html")
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
        let out = try run(fixture: "gmail-thread.html")
        #expect(out["chunkCount"] as? Int == 3, "1.2 MB in chunks of 512 KiB")
        #expect(out["chunksRoundTrip"] as? Bool == true)
        #expect(out["smallestChunk"] as? Int == 0)
    }
}

/// The service worker's modules, run in a headless Chromium with fake browser parts.
@Suite(.enabled(if: Chromium.binary != nil, "needs a Chromium: a Playwright headless shell, Chrome or Brave"))
struct ExtensionBackgroundTests {
    private func run() throws -> [String: Any] {
        try ExtensionHarness.run(fixture: "frames.html", attribute: "data-background")
    }

    @Test func oneOpenPortServesEveryReadAndTheHostBeingGoneFailsClosed() throws {
        let host = try #require(try run()["host"] as? [String: Any])
        #expect(host["connects"] as? Int == 1, "two messages, one port")
        #expect((host["sent"] as? [[String: Int]])?.map { $0["n"] } == [1, 2])
        let answers = try #require(host["answers"] as? [[String: Any]])
        #expect(answers.map { $0["kept"] as? Bool } == [true, false], "the replies came in the other order")
        for failed in ["whenTheHostDies", "askDuringTheWait", "whenNoHostIsInstalled"] {
            let answer = try #require(host[failed] as? [String: Any])
            #expect(answer["kept"] as? Bool == false && answer["error"] is String, "\(failed) is an error answer")
        }
        #expect(host["connectsDuringTheWait"] as? Int == 1, "no new port while the retry wait runs")
        #expect((host["afterTheWait"] as? [String: Any])?["kept"] as? Bool == true)
        #expect(host["connectsAfterTheWait"] as? Int == 2, "the port opens again after the wait")
        #expect(host["nothingWaitingAfterAFailure"] as? Bool == true)
    }

    @Test func aSlowCommandNeverHoldsAPageMessageBack() throws {
        let commands = try #require(try run()["commands"] as? [String: Any])
        #expect((commands["pageAnswer"] as? [String: Any])?["kept"] as? Bool == true, "the page was answered at once")
        #expect(commands["beforeSlowEnds"] as? [Int] == [42], "the quick command answered while the slow one ran")
        #expect(commands["afterSlowEnds"] as? [Int] == [42, 41], "the slow command answered when it ended")
        #expect(
            (commands["quickResult"] as? [String: Any])?["type"] as? String == "command_result",
            "a command is answered with its own id and type")
    }

    @Test func theAppBeingGoneFailsEveryWaitingMessageExactlyOnce() throws {
        let gone = try #require(try run()["appGone"] as? [String: Any])
        let answers = try #require(gone["answers"] as? [[Any]])
        #expect(answers.map { $0[0] as? Int } == [1, 2], "each waiting message was answered once")
        for answer in answers {
            let reply = try #require(answer[1] as? [String: Any])
            #expect(reply["kept"] as? Bool == false && reply["error"] is String)
        }
        #expect((gone["next"] as? [String: Any])?["kept"] as? Bool == true, "the same port serves the next message")
    }

    @Test func theDriverOpensReadsAndClosesEveryTabItOpened() throws {
        let driver = try #require(try run()["driver"] as? [String: Any])
        let opened = try #require(driver["opened"] as? [String: Any])
        let tab = try #require(opened["tab"] as? Int)
        #expect(opened["ok"] as? Bool == true)
        let created = try #require(driver["created"] as? [[String: Any]])
        #expect(created.allSatisfy { $0["active"] as? Bool == false }, "every tab opens inactive")
        let groupUpdates = try #require(driver["groupUpdates"] as? [[Any]])
        #expect(groupUpdates.count == 2)
        #expect(
            ExtensionHarness.same(groupUpdates[0][1], ["title": "Workbench", "collapsed": true]),
            "one collapsed group named Workbench")
        let grouped = try #require(driver["grouped"] as? [[String: Any]])
        #expect(grouped[1]["groupId"] as? Int == 7, "the second tab joins the same group")
        let read = try #require(driver["read"] as? [String: Any])
        #expect(read["text"] as? String == "text of \(tab) read" && read["title"] as? String == "T\(tab)")
        let stranger = driver["strangerRead"] as? [String: Any]
        #expect(stranger?["error"] as? String == "unknown_tab", "a tab the driver did not open")
        let click = driver["unknown"] as? [String: Any]
        #expect(click?["error"] as? String == "unknown_command", "no click command exists")
        #expect(driver["storedBeforeClose"] as? [Int] == created.compactMap { $0["id"] as? Int })
        let tabIds = driver["storedBeforeClose"] as? [Int]
        #expect(driver["removed"] as? [Int] == tabIds, "close_all closes exactly the opened tabs")
        #expect(driver["storedAfterClose"] as? [Int] == [])
    }

    @Test func aTabIsClosedWhenItsOpenFailsAndAfterAWorkerRestart() throws {
        let out = try run()
        let timeout = try #require(out["driverTimeout"] as? [String: Any])
        #expect((timeout["timedOut"] as? [String: Any])?["error"] as? String == "timeout")
        #expect((timeout["removed"] as? [Int])?.count == 1 && timeout["stored"] as? [Int] == [])
        #expect(timeout["listeners"] as? Int == 0, "the load listener is removed")
        let incognito = try #require(out["driverIncognito"] as? [String: Any])
        #expect((incognito["inPrivate"] as? [String: Any])?["error"] as? String == "incognito")
        #expect((incognito["removed"] as? [Int])?.count == 1 && incognito["stored"] as? [Int] == [])
        let restart = try #require(out["driverRestart"] as? [String: Any])
        #expect((restart["idsAtCrash"] as? [Int])?.count == 1)
        #expect(restart["removed"] as? [Int] == restart["idsAtCrash"] as? [Int], "the new worker closes the old tab")
        #expect(restart["stored"] as? [Int] == [])
        #expect((out["driverUnreadable"] as? [String: Any])?["error"] as? String == "unreadable")
        let stale = try #require((out["driverStaleGroup"] as? [String: Any])?["grouped"] as? [[String: Any]])
        #expect(stale.count == 3, "a refused group id falls back to a new group")
    }

    @Test func eachFrameSendsItsTextTaggedWithItsOwnAddress() throws {
        let messages = try #require(try run()["messages"] as? [String: Any])
        let top = try #require(messages["top"] as? [String: Any])
        #expect(top["url"] as? String == "https://app.example/view" && top["frame"] == nil)
        #expect(top["browser"] == nil, "the message names no browser; the app learns it from the process tree")
        let frame = try #require(messages["frame"] as? [String: Any])
        #expect(frame["url"] as? String == "https://app.example/view")
        #expect(frame["frame"] as? String == "https://widget.example/inside", "the frame is named by its own address")
        #expect(frame["text"] as? String == "words")
    }

    @Test func nothingIsSentWhenTheSenderIsNotAnOpenTab() throws {
        let messages = try #require(try run()["messages"] as? [String: Any])
        for dropped in [
            "frameWithoutTabAddress", "incognito", "noTab", "mailFromAnotherSite", "unknownKind",
        ] {
            #expect(messages[dropped] is NSNull, "\(dropped) sends nothing")
        }
        #expect(messages["topWithoutTabAddress"] is [String: Any], "a top frame is its own address")
        let mail = try #require(messages["mailFromGmail"] as? [String: Any])
        #expect(mail["type"] as? String == "mail")
        #expect((mail["context"] as? [String: Any])?["browser"] == nil)
        #expect(
            ExtensionHarness.same(messages["adapter"], ["type": "adapter_state", "site": "Gmail", "stale": true]))
    }

    @Test func aNavigationInsideAPageAsksThatFrameToReadAgain() throws {
        let posted = try #require(try run()["rereads"] as? [[Any]])
        #expect(posted.count == 2, "a tab with no port and a closed port are not posted to")
        #expect(posted.map { $0[0] as? String } == ["a", "b"])
        #expect(posted.allSatisfy { $0[1] as? String == "reread" })
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

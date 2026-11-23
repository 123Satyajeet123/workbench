import Foundation
import Kernel
import Synchronization
import Testing

@testable import WorkbenchCore

/// Runs the built `workbench-pages` host as the browser does: framed messages on stdin, framed replies on stdout. The
/// host opens no store; the app's listener, started here in this process, is the only writer. `scripts/pages-e2e.sh`
/// builds the host first.
@Suite struct PageHostProcessTests {
    static let owner = Result<PersonID, any Error>.success(try! PersonID("owner-1"))

    static let host = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../.build/debug/workbench-pages").standardized

    /// A host process as a browser runs it: stdin stays open until `finish`, and each frame the host writes is queued
    /// as it arrives.
    private final class HostSession: @unchecked Sendable {
        let process = Process()
        private let stdin = Pipe()
        private let stdout = Pipe()
        private let frames = Mutex<[Data]>([])

        init(socket: String) throws {
            process.executableURL = PageHostProcessTests.host
            process.environment = ["WORKBENCH_PAGES_SOCKET": socket]
            process.standardInput = stdin
            process.standardOutput = stdout
            try process.run()
            let output = stdout.fileHandleForReading
            Thread.detachNewThread { [self] in
                while case .message(let frame) = NativeMessage.next(read: { output.readData(ofLength: $0) }) {
                    frames.withLock { $0.append(frame) }
                }
            }
        }

        func send(_ message: Data) { sendRaw(NativeMessage.frame(message)) }

        func sendRaw(_ bytes: Data) { stdin.fileHandleForWriting.write(bytes) }

        /// The next frame the host wrote, or nil when none came within `seconds`.
        func next(within seconds: Double = 20) async -> Data? {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                if let frame = frames.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { return frame }
                try? await Task.sleep(for: .milliseconds(5))
            }
            return nil
        }

        func finish() {
            try? stdin.fileHandleForWriting.close()
            process.waitUntilExit()
        }
    }

    private static let appUnavailable = Data(#"{"type":"app_unavailable"}"#.utf8)

    /// Writes each message, waits for `replies` frames, then closes the input as a browser closing its port does.
    private func run(_ messages: [Data], socket: String, replies: Int? = nil) async throws -> [Data] {
        let session = try HostSession(socket: socket)
        messages.forEach(session.send)
        var answered: [Data] = []
        for _ in 0..<(replies ?? messages.count) { await session.next().map { answered.append($0) } }
        session.finish()
        return answered
    }

    private func replies(in frames: [Data]) throws -> [PageHost.Reply] {
        try frames.map { try JSONDecoder().decode(PageHost.Reply.self, from: $0) }
    }

    private func encoded(_ page: WebPage) throws -> Data { try JSONEncoder().encode(page) }

    private func page(saying text: String) -> WebPage {
        WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: text)
    }

    private func app(
        policy: CapturePolicy, owner: Result<PersonID, any Error> = Self.owner,
        browserOf: @escaping @Sendable (Int32) -> String? = { _ in "com.brave.Browser" }
    ) throws -> (store: Store, socket: String, listener: PageHostListener) {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(policy)
        let socket = shortSocketPath()
        return (store, socket, try PageHostListener(path: socket, store: store, owner: owner, browserOf: browserOf))
    }

    @Test func theHostProcessStoresAnAllowedPageAndNothingFromABrokenFrame() async throws {
        #expect(FileManager.default.isExecutableFile(atPath: Self.host.path), "build the host first")
        let (store, socket, listener) = try app(policy: CapturePolicy(switches: [.screen: true, .screenText: true]))
        defer { _ = listener }
        let page = WebPage(
            browser: "com.brave.Browser", url: "https://mail.example.com/", title: "Inbox", text: "Deck from Acme")
        #expect(try replies(in: try await run([try encoded(page)], socket: socket)) == [PageHost.Reply(kept: true)])
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).map(\.text) == ["Deck from Acme"])

        let session = try HostSession(socket: socket)
        session.sendRaw(Data([0xFF, 0xFF, 0xFF, 0x7F]) + Data("junk".utf8))
        session.process.waitUntilExit()
        #expect(await session.next(within: 0.2) == nil, "a broken frame ends the host; the browser sees the port close")
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).count == 1)
    }

    @Test func theHostProcessReassemblesADeckSentInChunksOverOneSession() async throws {
        let (store, socket, listener) = try app(
            policy: CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]]),
            owner: .success(try PersonID("owner-1")))
        defer { _ = listener }
        let context = MailContext(
            browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/Deals/FMfc",
            label: "Deals", threadId: "FMfc", messageId: "msg-1")
        let message = MailMessage(
            context: context, sender: "ana@acme.example", recipients: ["vc@fund.example"],
            text: "Acme raises a seed.", attachments: ["Deck.pdf"])
        let pieces = chunks(of: makeDeck([.text("Acme Seed Deck")]), name: "Deck.pdf", context: context, size: 700)
        let inputs = try [JSONEncoder().encode(message)] + pieces.map { try JSONEncoder().encode($0) }
        let replies = try replies(in: try await run(inputs, socket: socket))
        #expect(replies.map(\.kept) == [true] + Array(repeating: false, count: pieces.count - 1) + [true])
        #expect(replies[0].wantDecks == ["Deck.pdf"])
        #expect(
            try store.queries.mailParts(from: .distantPast, to: .distantFuture).map(\.text)
                == ["Acme raises a seed.", "Acme Seed Deck"])
    }

    /// The browser keeps stdin open until it has the reply (measured: Brave's host hung for minutes when the host
    /// waited for the end of input). The answer must come while the pipe is still open.
    @Test func theHostAnswersWhileTheBrowserKeepsThePipeOpen() async throws {
        let (store, socket, listener) = try app(policy: CapturePolicy(switches: [.screen: true, .screenText: true]))
        defer { _ = listener }
        let session = try HostSession(socket: socket)
        defer { session.finish() }
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "open pipe")
        session.send(try encoded(page))
        let message = try #require(await session.next(), "no answer while the pipe was open")
        #expect(try JSONDecoder().decode(PageHost.Reply.self, from: message) == PageHost.Reply(kept: true))
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).map(\.text) == ["open pipe"])
    }

    @Test func theReplyCarriesTheIdOfItsMessage() async throws {
        let (_, socket, listener) = try app(policy: CapturePolicy(switches: [.screen: true, .screenText: true]))
        defer { _ = listener }
        let page = #"{"id":17,"url":"https://site.example/","title":"t","text":"with an id"}"#
        let replies = try replies(in: try await run([Data(page.utf8)], socket: socket))
        #expect(replies == [PageHost.Reply(id: 17, kept: true)])
    }

    /// With no app listening, the host tells the extension with one constant frame for each message. Nothing is kept:
    /// the store folder is never created by the host, and no file of page text is left anywhere.
    @Test func theHostRefusesAndKeepsNothingWhenTheAppDoesNotRun() async throws {
        let socket = shortSocketPath()
        let page = try encoded(page(saying: "no app"))
        #expect(try await run([page, page], socket: socket) == [Self.appUnavailable, Self.appUnavailable])
        #expect(!FileManager.default.fileExists(atPath: socket))
    }

    @Test func theHostReachesAnAppThatStartsLaterAndRefusesAfterItStops() async throws {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let socket = shortSocketPath()
        let session = try HostSession(socket: socket)
        defer { session.finish() }
        let page = try encoded(page(saying: "later"))

        func ask() async throws -> Data {
            session.send(page)
            return try #require(await session.next(), "the host gave no answer")
        }

        #expect(try await ask() == Self.appUnavailable)
        var listener: PageHostListener? = try PageHostListener(
            path: socket, store: store, owner: Self.owner, browserOf: { _ in "com.brave.Browser" })
        #expect(try JSONDecoder().decode(PageHost.Reply.self, from: try await ask()) == PageHost.Reply(kept: true))
        listener = nil
        #expect(try await ask() == Self.appUnavailable, "the app is gone: nothing is kept")
        _ = listener
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).map(\.text) == ["later"])
    }

    @Test func theAppBeingGoneIsToldOnceWhetherOrNotAMessageWaits() async throws {
        let store = try Store(directory: temporaryDirectory())
        let socket = shortSocketPath()
        var listener: PageHostListener? = try PageHostListener(
            path: socket, store: store, owner: Self.owner, browserOf: { _ in "com.brave.Browser" })
        let session = try HostSession(socket: socket)
        defer { session.finish() }
        session.send(try encoded(WebPage(browser: "", url: "https://site.example/", title: "t", text: "first")))
        _ = try #require(await session.next(), "the app answered")
        listener = nil
        _ = listener
        #expect(await session.next(within: 20) == Self.appUnavailable)
        #expect(await session.next(within: 0.5) == nil, "one frame for one loss")
    }

    @Test func aProcessOfAnotherUserIsRefusedAndKeepsNothing() async throws {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let socket = shortSocketPath()
        let listener = try PageHostListener(path: socket, store: store, owner: Self.owner, user: geteuid() &+ 1)
        let page = try encoded(page(saying: "stranger"))
        #expect(try await run([page], socket: socket) == [Self.appUnavailable])
        #expect(try store.queries.pageLines(from: .distantPast, to: .distantFuture).isEmpty)
        _ = listener
    }

    @Test func theSocketLeftByAnAppThatDiedIsReplaced() async throws {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let stale = shortSocketPath()
        FileManager.default.createFile(atPath: stale, contents: Data("left behind".utf8))
        let listener = try PageHostListener(
            path: stale, store: store, owner: Self.owner, browserOf: { _ in "com.brave.Browser" })
        let page = try encoded(page(saying: "later"))
        #expect(try replies(in: try await run([page], socket: stale)) == [PageHost.Reply(kept: true)])
        _ = listener
    }

    /// A command from the app reaches the browser through the host, and its result goes back to the waiting caller. A
    /// page message is answered at once while the command still waits.
    @Test func aCommandReachesTheBrowserWhileAPageMessageIsAnsweredAtOnce() async throws {
        let (_, socket, listener) = try app(policy: CapturePolicy(switches: [.screen: true, .screenText: true]))
        let session = try HostSession(socket: socket)
        defer { session.finish() }
        session.send(try encoded(WebPage(browser: "", url: "https://site.example/", title: "t", text: "hello")))
        _ = try #require(await session.next())

        async let result = listener.send(.closeAll, timeout: 20)
        let command = try #require(await session.next(), "no command reached the browser")
        let sent = try #require(try JSONSerialization.jsonObject(with: command) as? [String: Any])
        #expect(sent["type"] as? String == "command" && sent["command"] as? String == "close_all")
        let id = try #require(sent["id"] as? Int)

        session.send(try encoded(WebPage(browser: "", url: "https://site.example/", title: "t", text: "while waiting")))
        let answered = try #require(await session.next(), "the page message waited behind the command")
        #expect(try JSONDecoder().decode(PageHost.Reply.self, from: answered).kept)

        session.send(Data(#"{"type":"command_result","id":\#(id),"ok":true,"closed":2}"#.utf8))
        #expect(try await result == DriverReply(id: id, ok: true, closed: 2))
    }

    @Test func noCommandGoesToAConnectionWhoseBrowserIsUnknownOrNotAllowed() async throws {
        for browser: String? in [nil, "com.evil.app"] {
            let (_, socket, listener) = try app(policy: CapturePolicy(), browserOf: { _ in browser })
            let session = try HostSession(socket: socket)
            defer { session.finish() }
            session.send(try encoded(WebPage(browser: "", url: "https://site.example/", title: "t", text: "x")))
            _ = try #require(await session.next())
            await #expect(throws: DriverFailure.noBrowserConnected) { try await listener.send(.closeAll, timeout: 1) }
        }
        let (_, socket, listener) = try app(policy: CapturePolicy())
        let session = try HostSession(socket: socket)
        defer { session.finish() }
        session.send(try encoded(WebPage(browser: "", url: "https://site.example/", title: "t", text: "x")))
        _ = try #require(await session.next())
        #expect(listener.connectedBrowsers.map(\.browser) == ["com.brave.Browser"], "a known browser is the control")
    }

    @Test func aCommandWaitingWhenTheConnectionEndsFailsAndNoneHangs() async throws {
        let (_, socket, listener) = try app(policy: CapturePolicy())
        let session = try HostSession(socket: socket)
        session.send(try encoded(WebPage(browser: "", url: "https://site.example/", title: "t", text: "x")))
        _ = try #require(await session.next())
        let pending = Task { try await listener.send(.closeAll, timeout: 20) }
        _ = try #require(await session.next(), "the command reached the browser")
        session.finish()
        await #expect(throws: DriverFailure.connectionLost) { try await pending.value }
        await #expect(throws: DriverFailure.noBrowserConnected) { try await listener.send(.closeAll, timeout: 1) }
    }

    @Test func aCommandTheBrowserNeverAnswersFailsWithATimeout() async throws {
        let (_, socket, listener) = try app(policy: CapturePolicy())
        let session = try HostSession(socket: socket)
        defer { session.finish() }
        session.send(try encoded(WebPage(browser: "", url: "https://site.example/", title: "t", text: "x")))
        _ = try #require(await session.next())
        await #expect(throws: DriverFailure.timedOut) { try await listener.send(.closeAll, timeout: 0.3) }
    }

    /// A stand-in browser: a copy of bash inside `Fake Browser.app`, with the bundle id Brave has. It starts the
    /// host as its child, as a browser does, and the host reads the framed messages from a file.
    private func runUnderFakeBrowser(_ input: Data, socket: String) throws -> Data {
        let root = temporaryDirectory()
        let contents = root.appending(path: "Fake Browser.app/Contents")
        try FileManager.default.createDirectory(
            at: contents.appending(path: "MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.brave.Browser", "CFBundleName": "Fake Browser"]
        try (plist as NSDictionary).write(to: contents.appending(path: "Info.plist"))
        let browser = contents.appending(path: "MacOS/Browser")
        try FileManager.default.copyItem(at: URL(filePath: "/bin/bash"), to: browser)
        let signer = Process()
        signer.executableURL = URL(filePath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", browser.path]
        signer.standardError = FileHandle.nullDevice
        try signer.run()
        signer.waitUntilExit()
        let (inputFile, outputFile) = (root.appending(path: "in"), root.appending(path: "out"))
        try input.write(to: inputFile)
        let process = Process()
        process.executableURL = browser
        process.arguments = [
            "-c", "{ cat '\(inputFile.path)'; sleep 1; } | '\(Self.host.path)' > '\(outputFile.path)'; true",
        ]
        process.environment = ["WORKBENCH_PAGES_SOCKET": socket]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: outputFile)
    }

    private func frames(in output: Data) throws -> [Data] {
        var rest = output
        var frames: [Data] = []
        while let (frame, used) = try NativeMessage.first(in: rest) {
            frames.append(frame)
            rest = rest.dropFirst(used)
        }
        return frames
    }

    /// The live parent chain: the host's parent is the process of the browser app, found from the process tree.
    @Test func theAppNamesTheBrowserFromTheProcessThatStartedTheHost() async throws {
        let (store, socket, listener) = try app(
            policy: CapturePolicy(switches: [.screen: true, .screenText: true]),
            browserOf: PeerBrowser.bundleID(ofPeer:))
        defer { _ = listener }
        let page = WebPage(
            browser: "com.evil.app", url: "https://site.example/", title: "t", text: "from the fake browser")
        let output = try runUnderFakeBrowser(NativeMessage.frame(try encoded(page)), socket: socket)
        let answers = try replies(in: try frames(in: output))
        #expect(answers == [PageHost.Reply(kept: true)], "\(answers)")
        #expect(
            try store.queries.pageLines(from: .distantPast, to: .distantFuture).map(\.text) == [
                "from the fake browser"
            ],
            "kept: the app named the parent's browser, not the browser the message claimed")
    }

    @Test func aHostNotStartedByABrowserAppKeepsNothingAndTheReplyNamesWhy() async throws {
        let (store, socket, listener) = try app(
            policy: CapturePolicy(switches: [.screen: true, .screenText: true]),
            browserOf: PeerBrowser.bundleID(ofPeer:))
        defer { _ = listener }
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "forged")
        let reply = try #require(try replies(in: try await run([try encoded(page)], socket: socket)).first)
        #expect(reply.kept == false && reply.error == PageHost.unknownBrowser, "the test process is no browser app")
        #expect(
            try store.queries.pageLines(from: .distantPast, to: .distantFuture).isEmpty,
            "a message that says Brave changes nothing")
    }

    @Test func aSocketPathThatDoesNotFitIsRefusedWithItsLength() {
        let long = String(repeating: "a", count: 200)
        #expect(throws: PagesSocket.Failure.pathTooLong(200)) { try PagesSocket.address(of: long) }
    }
}

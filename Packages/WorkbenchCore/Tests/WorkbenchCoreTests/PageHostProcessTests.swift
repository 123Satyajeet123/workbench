import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

/// Runs the built `workbench-pages` host as the browser does: framed messages on stdin, framed replies on stdout. The
/// host opens no store; the app's listener, started here in this process, is the only writer. `scripts/pages-e2e.sh`
/// builds the host first.
@Suite struct PageHostProcessTests {
    static let host = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../.build/debug/workbench-pages").standardized

    private func hostProcess(socket: String) -> (process: Process, stdin: Pipe, stdout: Pipe) {
        let process = Process()
        process.executableURL = Self.host
        process.environment = ["WORKBENCH_PAGES_SOCKET": socket]
        let (stdin, stdout) = (Pipe(), Pipe())
        process.standardInput = stdin
        process.standardOutput = stdout
        return (process, stdin, stdout)
    }

    private func run(_ input: Data, socket: String) throws -> Data {
        let (process, stdin, stdout) = hostProcess(socket: socket)
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return output
    }

    private func replies(in output: Data) throws -> [PageHost.Reply] {
        var rest = output
        var replies: [PageHost.Reply] = []
        while let (reply, used) = try NativeMessage.first(in: rest) {
            replies.append(try JSONDecoder().decode(PageHost.Reply.self, from: reply))
            rest = rest.dropFirst(used)
        }
        return replies
    }

    private func app(
        policy: CapturePolicy, browserOf: @escaping @Sendable (Int32) -> String? = { _ in "com.brave.Browser" }
    ) throws -> (store: Store, socket: String, listener: PageHostListener) {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(policy)
        let socket = shortSocketPath()
        return (store, socket, try PageHostListener(path: socket, store: store, browserOf: browserOf))
    }

    @Test func theHostProcessStoresAnAllowedPageAndNothingFromABrokenFrame() throws {
        #expect(FileManager.default.isExecutableFile(atPath: Self.host.path), "build the host first")
        let (store, socket, listener) = try app(policy: CapturePolicy(switches: [.screen: true, .screenText: true]))
        defer { _ = listener }
        let page = WebPage(
            browser: "com.brave.Browser", url: "https://mail.example.com/", title: "Inbox", text: "Deck from Acme")
        let output = try run(NativeMessage.frame(try JSONEncoder().encode(page)), socket: socket)
        #expect(try replies(in: output) == [PageHost.Reply(kept: true)])
        #expect(try store.queries.activities(since: .distantPast).compactMap(\.text) == ["Deck from Acme"])

        let broken = try replies(in: try run(Data([0xFF, 0xFF, 0xFF, 0x7F]) + Data("junk".utf8), socket: socket))
        #expect(broken.map(\.kept) == [false] && broken[0].error == "\(NativeMessage.Failure.tooLong(0x7FFF_FFFF))")
        #expect(try store.queries.activities(since: .distantPast).count == 1)
    }

    @Test func theHostProcessReassemblesADeckSentInChunksOverOneSession() throws {
        let (store, socket, listener) = try app(
            policy: CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]]))
        defer { _ = listener }
        let context = MailContext(
            browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/Deals/FMfc",
            label: "Deals", threadId: "FMfc", messageId: "msg-1")
        let message = MailMessage(
            context: context, sender: "Ana", subject: "Acme", text: "Acme raises a seed.", attachments: ["Deck.pdf"])
        let pieces = chunks(of: makeDeck([.text("Acme Seed Deck")]), name: "Deck.pdf", context: context, size: 700)
        var input = try NativeMessage.frame(JSONEncoder().encode(message))
        for piece in pieces { input += try NativeMessage.frame(JSONEncoder().encode(piece)) }
        let replies = try replies(in: try run(input, socket: socket))
        #expect(replies.map(\.kept) == [true] + Array(repeating: false, count: pieces.count - 1) + [true])
        #expect(replies[0].wantDecks == ["Deck.pdf"])
        #expect(
            try store.queries.mailParts(from: .distantPast, to: .distantFuture).map(\.text)
                == ["Acme raises a seed.", "Acme Seed Deck"])
    }

    /// The browser keeps stdin open until it has the reply (measured: Brave's host hung for minutes when the host
    /// waited for the end of input). The answer must come while the pipe is still open.
    @Test func theHostAnswersWhileTheBrowserKeepsThePipeOpen() throws {
        let (store, socket, listener) = try app(policy: CapturePolicy(switches: [.screen: true, .screenText: true]))
        defer { _ = listener }
        let (process, stdin, stdout) = hostProcess(socket: socket)
        try process.run()
        defer { process.terminate() }
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "open pipe")
        stdin.fileHandleForWriting.write(NativeMessage.frame(try JSONEncoder().encode(page)))
        let reply = Mutex<Data?>(nil)
        let answered = DispatchSemaphore(value: 0)
        let output = stdout.fileHandleForReading
        DispatchQueue.global().async {
            let header = output.readData(ofLength: 4)
            let length = header.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            reply.withLock { $0 = output.readData(ofLength: length) }
            answered.signal()
        }
        #expect(answered.wait(timeout: .now() + 20) == .success, "no answer while the pipe was open")
        let message = try #require(reply.withLock { $0 })
        #expect(try JSONDecoder().decode(PageHost.Reply.self, from: message) == PageHost.Reply(kept: true))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(try store.queries.activities(since: .distantPast).compactMap(\.text) == ["open pipe"])
    }

    /// With no app listening, the host refuses each message and tells the extension. Nothing is kept: the store folder
    /// is never created by the host, and no file of page text is left anywhere.
    @Test func theHostRefusesAndKeepsNothingWhenTheAppDoesNotRun() throws {
        let socket = shortSocketPath()
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "no app")
        let frame = NativeMessage.frame(try JSONEncoder().encode(page))
        let replies = try replies(in: try run(frame + frame, socket: socket))
        #expect(replies.count == 2)
        #expect(replies.allSatisfy { $0.kept == false && $0.error == PagesRelay.notRunning })
        #expect(!FileManager.default.fileExists(atPath: socket))
    }

    @Test func theHostReachesAnAppThatStartsLaterAndRefusesAfterItStops() throws {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let socket = shortSocketPath()
        let (process, stdin, stdout) = hostProcess(socket: socket)
        try process.run()
        defer { process.terminate() }
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "later")
        let frame = NativeMessage.frame(try JSONEncoder().encode(page))

        func ask() throws -> PageHost.Reply {
            stdin.fileHandleForWriting.write(frame)
            let answer = Mutex<Data?>(nil)
            let answered = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                let header = stdout.fileHandleForReading.readData(ofLength: 4)
                let length = header.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
                answer.withLock { $0 = stdout.fileHandleForReading.readData(ofLength: length) }
                answered.signal()
            }
            #expect(answered.wait(timeout: .now() + 20) == .success, "the host gave no answer")
            return try JSONDecoder().decode(PageHost.Reply.self, from: try #require(answer.withLock { $0 }))
        }

        #expect(try ask().error == PagesRelay.notRunning)
        var listener: PageHostListener? = try PageHostListener(
            path: socket, store: store, browserOf: { _ in "com.brave.Browser" })
        #expect(try ask() == PageHost.Reply(kept: true))
        listener = nil
        #expect(try ask().error == PagesRelay.notRunning, "the app is gone: nothing is kept")
        _ = listener
        #expect(try store.queries.activities(since: .distantPast).compactMap(\.text) == ["later"])
    }

    @Test func aProcessOfAnotherUserIsRefusedAndKeepsNothing() throws {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let socket = shortSocketPath()
        let listener = try PageHostListener(path: socket, store: store, user: geteuid() &+ 1)
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "stranger")
        let replies = try replies(in: try run(NativeMessage.frame(try JSONEncoder().encode(page)), socket: socket))
        #expect(replies.map(\.error) == [PagesRelay.notRunning])
        #expect(try store.queries.activities(since: .distantPast).isEmpty)
        _ = listener
    }

    @Test func theSocketLeftByAnAppThatDiedIsReplaced() throws {
        let store = try Store(directory: temporaryDirectory())
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let stale = shortSocketPath()
        FileManager.default.createFile(atPath: stale, contents: Data("left behind".utf8))
        let listener = try PageHostListener(path: stale, store: store, browserOf: { _ in "com.brave.Browser" })
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "later")
        let frame = NativeMessage.frame(try JSONEncoder().encode(page))
        #expect(try replies(in: try run(frame, socket: stale)) == [PageHost.Reply(kept: true)])
        _ = listener
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
        process.arguments = ["-c", "'\(Self.host.path)' < '\(inputFile.path)' > '\(outputFile.path)'; true"]
        process.environment = ["WORKBENCH_PAGES_SOCKET": socket]
        try process.run()
        process.waitUntilExit()
        return try Data(contentsOf: outputFile)
    }

    /// The live parent chain: the host's parent is the process of the browser app, found from the process tree.
    @Test func theAppNamesTheBrowserFromTheProcessThatStartedTheHost() throws {
        let (store, socket, listener) = try app(
            policy: CapturePolicy(switches: [.screen: true, .screenText: true]),
            browserOf: PeerBrowser.bundleID(ofPeer:))
        defer { _ = listener }
        let page = WebPage(
            browser: "com.evil.app", url: "https://site.example/", title: "t", text: "from the fake browser")
        let output = try runUnderFakeBrowser(NativeMessage.frame(try JSONEncoder().encode(page)), socket: socket)
        let answers = try replies(in: output)
        #expect(answers == [PageHost.Reply(kept: true)], "\(answers)")
        let kept = try #require(try store.queries.activities(since: .distantPast).first)
        #expect(kept.bundleID == "com.brave.Browser" && kept.app == "Brave Browser", "the bundle id of the parent app")
    }

    @Test func aHostNotStartedByABrowserAppKeepsNothingAndTheReplyNamesWhy() throws {
        let (store, socket, listener) = try app(
            policy: CapturePolicy(switches: [.screen: true, .screenText: true]),
            browserOf: PeerBrowser.bundleID(ofPeer:))
        defer { _ = listener }
        let page = WebPage(browser: "com.brave.Browser", url: "https://site.example/", title: "t", text: "forged")
        let output = try run(NativeMessage.frame(try JSONEncoder().encode(page)), socket: socket)
        let reply = try #require(try replies(in: output).first)
        #expect(reply.kept == false && reply.error == PageHost.unknownBrowser, "the test process is no browser app")
        #expect(try store.queries.activities(since: .distantPast).isEmpty, "a message that says Brave changes nothing")
    }

    @Test func aSocketPathThatDoesNotFitIsRefusedWithItsLength() {
        let long = String(repeating: "a", count: 200)
        #expect(throws: PagesSocket.Failure.pathTooLong(200)) { try PagesSocket.address(of: long) }
    }
}

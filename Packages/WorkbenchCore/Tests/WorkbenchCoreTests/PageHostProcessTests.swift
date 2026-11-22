import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

@Suite struct PageHostProcessTests {
    private let host = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../.build/debug/workbench-pages").standardized

    private func run(_ input: Data, store folder: URL) throws -> Data {
        let process = Process()
        process.executableURL = host
        process.environment = ["WORKBENCH_STORE": folder.path]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return output
    }

    @Test func theHostProcessStoresAnAllowedPageAndNothingFromABrokenFrame() throws {
        #expect(FileManager.default.isExecutableFile(atPath: host.path), "build the host first")
        let folder = temporaryDirectory()
        let store = try Store(directory: folder)
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let page = WebPage(
            browser: "com.brave.Browser", url: "https://mail.example.com/", title: "Inbox", text: "Deck from Acme")
        let output = try run(NativeMessage.frame(try JSONEncoder().encode(page)), store: folder)
        let (reply, _) = try #require(try NativeMessage.first(in: output))
        #expect(try JSONDecoder().decode(PageHost.Reply.self, from: reply) == PageHost.Reply(kept: true))
        #expect(try store.queries.activities(since: .distantPast).compactMap(\.text) == ["Deck from Acme"])

        _ = try run(Data([0xFF, 0xFF, 0xFF, 0x7F]) + Data("junk".utf8), store: folder)
        #expect(try store.queries.activities(since: .distantPast).count == 1)
    }

    @Test func theHostProcessReassemblesADeckSentInChunksOverOneSession() throws {
        let folder = temporaryDirectory()
        let store = try Store(directory: folder)
        try store.savePolicy(CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]]))
        let context = MailContext(
            browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/Deals/FMfc",
            label: "Deals", threadId: "FMfc", messageId: "msg-1")
        let message = MailMessage(
            context: context, sender: "Ana", subject: "Acme", text: "Acme raises a seed.", attachments: ["Deck.pdf"])
        let pieces = chunks(of: makeDeck([.text("Acme Seed Deck")]), name: "Deck.pdf", context: context, size: 700)
        var input = try NativeMessage.frame(JSONEncoder().encode(message))
        for piece in pieces { input += try NativeMessage.frame(JSONEncoder().encode(piece)) }
        var output = try run(input, store: folder)
        var replies: [PageHost.Reply] = []
        while let (reply, used) = try NativeMessage.first(in: output) {
            replies.append(try JSONDecoder().decode(PageHost.Reply.self, from: reply))
            output = output.dropFirst(used)
        }
        #expect(replies.map(\.kept) == [true] + Array(repeating: false, count: pieces.count - 1) + [true])
        #expect(replies[0].wantDecks == ["Deck.pdf"])
        #expect(
            try store.queries.mailParts(from: .distantPast, to: .distantFuture).map(\.text)
                == ["Acme raises a seed.", "Acme Seed Deck"])
    }

    /// The browser keeps stdin open until it has the reply (measured: Brave's host hung for minutes when the host
    /// waited for the end of input). The answer must come while the pipe is still open.
    @Test func theHostAnswersWhileTheBrowserKeepsThePipeOpen() throws {
        let folder = temporaryDirectory()
        let store = try Store(directory: folder)
        try store.savePolicy(CapturePolicy(switches: [.screen: true, .screenText: true]))
        let process = Process()
        process.executableURL = host
        process.environment = ["WORKBENCH_STORE": folder.path]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
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
        #expect(answered.wait(timeout: .now() + 5) == .success, "no answer while the pipe was open")
        let message = try #require(reply.withLock { $0 })
        #expect(try JSONDecoder().decode(PageHost.Reply.self, from: message) == PageHost.Reply(kept: true))
        try stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        #expect(try store.queries.activities(since: .distantPast).compactMap(\.text) == ["open pipe"])
    }
}

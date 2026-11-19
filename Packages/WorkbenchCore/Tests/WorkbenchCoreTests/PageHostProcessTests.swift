import Foundation
import Testing

@testable import WorkbenchCore

/// Runs the built `workbench-pages` host as the browser does: framed messages on stdin, framed replies on stdout.
/// `scripts/pages-e2e.sh` builds it first.
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
            browser: "com.brave.Browser", url: "https://mail.google.com/", title: "Inbox", text: "Deck from Acme")
        let output = try run(NativeMessage.frame(try JSONEncoder().encode(page)), store: folder)
        let (reply, _) = try #require(try NativeMessage.first(in: output))
        #expect(try JSONDecoder().decode(PageHost.Reply.self, from: reply) == PageHost.Reply(kept: true))
        #expect(try store.queries.activities(since: .distantPast).compactMap(\.text) == ["Deck from Acme"])

        _ = try run(Data([0xFF, 0xFF, 0xFF, 0x7F]) + Data("junk".utf8), store: folder)
        #expect(try store.queries.activities(since: .distantPast).count == 1)
    }
}

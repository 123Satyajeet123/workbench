import Foundation
import Testing

@testable import WorkbenchCore

private final class TestBundleAnchor {}

/// Only the app writes the store. The host is a relay: no store, no SQLite, no consent code is linked into it.
@Suite struct OneWriterTests {
    private static let sources = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources").standardized

    /// The imports of every file in a target's folder.
    private func imports(ofTarget target: String) throws -> Set<String> {
        let folder = Self.sources.appending(path: target)
        let walker = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var found: Set<String> = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: #/(?m)^(?:@_exported )?import (\w+)/#) { found.insert(String(match.1)) }
        }
        return found
    }

    /// Whether the executable holds a symbol of GRDB or SQLite.
    static func linksSQLite(_ binary: URL) throws -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/nm")
        process.arguments = [binary.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let symbols = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return symbols.contains("GRDB") || symbols.contains("sqlite3_open")
    }

    @Test func theHostAndItsRelayImportNothingThatOpensAStore() throws {
        let allowed: Set<String> = ["Foundation", "Darwin", "PagesRelay"]
        #expect(try imports(ofTarget: "WorkbenchPages").subtracting(allowed).isEmpty)
        #expect(try imports(ofTarget: "PagesRelay").subtracting(allowed).isEmpty)
        #expect(try imports(ofTarget: "WorkbenchPages").isSuperset(of: ["PagesRelay"]), "the scan reads the host")
    }

    @Test func theBuiltHostLinksNoStoreAndTheCheckSeesOneWhenThereIs() throws {
        #expect(FileManager.default.isExecutableFile(atPath: PageHostProcessTests.host.path), "build the host first")
        #expect(try !Self.linksSQLite(PageHostProcessTests.host))
        let test = try #require(Bundle(for: TestBundleAnchor.self).executableURL)
        #expect(try Self.linksSQLite(test), "the check finds the store in a binary that links it")
    }

    @Test func theStoreIsOpenedOnlyByTheApp() throws {
        let root = Self.sources.appending(path: "../..")
        var openers: [String] = []
        for package in ["WorkbenchCore", "BaseKit", "WorkbenchUI"] {
            let folder = root.appending(path: "\(package)/Sources").standardized
            let walker = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
            for case let file as URL in walker where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.contains("Store(directory:") { openers.append(file.lastPathComponent) }
            }
        }
        #expect(
            openers.sorted() == ["AppLaunch.swift", "LifecycleDryRun.swift"],
            "\(openers): the dry run opens a copy of a store in a temporary folder, never the store itself")
    }
}

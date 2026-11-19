import Foundation
import Testing

@testable import GoogleConnector

struct SourceHostScanTests {
    static let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "Sources")

    static func foreignHosts(in text: String) -> [String] {
        text.matches(of: #/https?:\/\/([A-Za-z0-9.-]+)/#).map { String($0.1).lowercased() }
            .filter { !GoogleHostGuard.allowedHosts.contains($0) }
    }

    @Test func plantedHostIsCaughtAndGoogleHostsPass() {
        #expect(Self.foreignHosts(in: #"URL(string: "https://telemetry.example.com/v1")"#) == ["telemetry.example.com"])
        #expect(Self.foreignHosts(in: #"URL(string: "https://www.googleapis.com/calendar/v3")"#).isEmpty)
    }

    @Test func ownSourcesNameOnlyTheFourGoogleHosts() throws {
        let walker = try #require(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        var scanned = 0
        var foreign: [String] = []
        for case let file as URL in walker where file.pathExtension == "swift" {
            scanned += 1
            foreign += Self.foreignHosts(in: try String(contentsOf: file, encoding: .utf8))
        }
        #expect(scanned >= 10, "the scan must see the sources")
        #expect(foreign.isEmpty, "\(foreign)")
    }
}

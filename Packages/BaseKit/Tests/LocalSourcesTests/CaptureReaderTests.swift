import AppKit
import CoreServices
import Foundation
import Testing

@testable import LocalSources

enum ActingScan {
    static let patterns = [
        #"\bAXUIElementSetAttributeValue\b"#, #"\bAXUIElementPerformAction\b"#, #"\bAXUIElementPostKeyboardEvent\b"#,
        #"\bCGEvent\w*Post\w*\b"#, #"\.post\(tap:"#, #"\bactivate\(options:"#, #"\.activate\(\)"#,
        #"\bNSAppleScript\b"#, #"\bopenApplication\b"#,
    ]

    static func hits(in text: String) -> [String] {
        patterns.filter { text.range(of: $0, options: .regularExpression) != nil }
    }

    static var readerFiles: [URL] {
        let folder = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Sources/LocalSources").standardized
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "swift" }
    }
}

struct ReadOnlyTests {
    @Test func noReaderActsOnAnotherApp() throws {
        let files = ActingScan.readerFiles
        #expect(Set(files.map(\.lastPathComponent)).isSuperset(of: ["ScreenReader.swift", "FileWatcher.swift"]))
        for file in files {
            #expect(
                ActingScan.hits(in: try String(contentsOf: file, encoding: .utf8)).isEmpty, "\(file.lastPathComponent)")
        }
    }

    @Test func theScanCatchesActionsAndPassesReads() {
        #expect(
            ActingScan.hits(in: #"AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, x)"#).count
                == 1)
        #expect(ActingScan.hits(in: "AXUIElementPerformAction(button, kAXPressAction)").count == 1)
        #expect(
            ActingScan.hits(
                in: "CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)?.post(tap: .cghidEventTap)"
            ).count == 1)
        #expect(ActingScan.hits(in: "AXUIElementCopyAttributeValue(window, kAXTitleAttribute, &value)").isEmpty)
    }
}

@MainActor
struct FrontAppTests {
    @Test func workbenchNeverReadsItsOwnWindowButReadsOtherApps() throws {
        let front = try #require(NSWorkspace.shared.frontmostApplication, "a test Mac has a front app")
        #expect(FrontApp.current(ownProcess: front.processIdentifier) == nil)
        #expect(FrontApp.current(ownProcess: -1)?.pid == front.processIdentifier)
    }
}

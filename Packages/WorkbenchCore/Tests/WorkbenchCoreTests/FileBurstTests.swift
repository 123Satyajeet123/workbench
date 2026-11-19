import Foundation
import Testing

@testable import WorkbenchCore

/// Measured on the founder's store (2026-11-19): a repository clone wrote 119,356 file rows in 90 minutes.
@Suite struct FileBurstTests {
    private let policy = CapturePolicy(switches: [.files: true])

    @Test func aBurstOfFilesKeepsAtMostTheWindowsCapAndTheNextWindowKeepsAgain() {
        var engine = CaptureEngine()
        let kept = (0..<500).compactMap {
            engine.observe(
                .create, path: "/Users/me/Projects/x/refs/f\($0).py", policy: policy,
                at: t0.addingTimeInterval(Double($0) / 50))
        }
        #expect(kept.count == engine.filesPerWindow)
        let later = engine.observe(
            .modify, path: "/Users/me/Projects/x/main.swift", policy: policy, at: t0.addingTimeInterval(61))
        #expect(later != nil)
    }

    @Test func aPersonsFewEditsAreAllKeptAndARepeatWithinTheWindowOnce() {
        var engine = CaptureEngine()
        let edits = (0..<10).compactMap {
            engine.observe(
                .modify, path: "/Users/me/Projects/x/file\($0 % 5).swift", policy: policy,
                at: t0.addingTimeInterval(Double($0)))
        }
        #expect(edits.count == 5)
    }
}

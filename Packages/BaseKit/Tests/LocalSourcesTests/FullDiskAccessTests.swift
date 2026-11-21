import Foundation
import Testing

@testable import LocalSources

@Suite struct FullDiskAccessTests {
    @Test func aProbeTheSystemWillNotOpenMeansNoAccess() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "fda-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let probe = folder.appending(path: "TCC.db")
        try Data("x".utf8).write(to: probe)
        #expect(FullDiskAccess.isGranted(probe: probe.path))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: probe.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: probe.path) }
        #expect(!FullDiskAccess.isGranted(probe: probe.path))
    }

    @Test func aMissingProbeIsNotAccess() {
        #expect(!FullDiskAccess.isGranted(probe: "/nonexistent-\(UUID().uuidString)"))
    }

    @Test func theProbeIsTheSystemWideFileEveryMacHas() {
        #expect(FullDiskAccess.defaultProbe == "/Library/Application Support/com.apple.TCC/TCC.db")
    }
}

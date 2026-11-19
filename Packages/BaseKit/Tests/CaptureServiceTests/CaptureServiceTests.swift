import Foundation
import LocalSources
import Testing
import WorkbenchCore

@testable import CaptureService

@MainActor
struct CaptureServiceTests {
    private func service() throws -> (CaptureService, Store) {
        let store = try Store(
            directory: FileManager.default.temporaryDirectory.appending(path: "cs-\(UUID().uuidString)"))
        return (try CaptureService(store: store), store)
    }

    @Test func aFreshServiceCapturesNothingAndAnUpdateIsSavedAsOneConsentRow() throws {
        let (service, store) = try service()
        #expect(service.status == .off)
        try service.update { $0.switches[.files] = true }
        #expect(service.status == .capturing)
        #expect(try store.currentPolicy().isEnabled(.files))
        try service.update { $0.switches[.files] = true }
        #expect(try store.queries.count(of: .consent) == 1)
    }

    @Test func pausedAndPrivateModesShowAsSuchAndTheClockEndsThem() throws {
        let (service, store) = try service()
        let hour = store.clock().addingTimeInterval(3600)
        try service.update {
            $0.switches[.files] = true
            $0.mode = .paused(until: hour)
        }
        #expect(service.status == .paused)
        try service.update { $0.mode = .paused(until: store.clock().addingTimeInterval(-1)) }
        #expect(service.status == .capturing)
    }

    @Test func theKeptTodayListHoldsWindowsAndFilesAndForgetRemovesOne() throws {
        let (service, store) = try service()
        var engine = CaptureEngine()
        let policy = CapturePolicy(switches: [.files: true])
        let batch = engine.observe(.modify, path: "/p/a.swift", policy: policy, at: store.clock())
        try store.record(#require(batch))
        let kept = try service.keptToday(limit: 20)
        #expect(kept.count == 1)
        try service.forget(kept[0])
        #expect(try service.keptToday(limit: 20).isEmpty)
    }

    @Test func aCallIsRefusedUntilSwitchedOnOrWhilePausedAndAsksFirstInPrivateMode() async throws {
        let (service, store) = try service()
        let brave = AudioApp(bundleID: "com.brave.Browser", name: "Brave", processes: [1])
        let hour = store.clock().addingTimeInterval(3600)
        await #expect(throws: CallStartError.denied(.sourceSwitchedOff)) { try await service.startCall(in: brave) }
        try service.update {
            $0.switches[.call] = true
            $0.mode = .paused(until: hour)
        }
        await #expect(throws: CallStartError.denied(.paused)) { try await service.startCall(in: brave) }
        try service.update { $0.mode = .privateMode(until: hour) }
        await #expect(throws: CallStartError.needsConfirmation) { try await service.startCall(in: brave) }
        try service.update {
            $0.denyList[.call] = ["com.brave.Browser"]
            $0.mode = .on
        }
        await #expect(throws: CallStartError.denied(.labelDenied)) { try await service.startCall(in: brave) }
        #expect(service.call == nil)
        #expect(try store.queries.recordings().isEmpty)
    }

    @Test func stoppingWithNoCallDoesNothing() throws {
        let (service, store) = try service()
        try service.stopCall()
        #expect(try store.queries.recordings().isEmpty)
    }
}

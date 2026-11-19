import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct CapturePolicyTests {
    private let files = CaptureRequest(kind: .files, label: "/Users/a/Projects/x.swift")
    private let filesOn = CapturePolicy(switches: [.files: true])

    @Test func pausedDeniesBeforeTheEndAndAllowsAfter() {
        var policy = filesOn
        policy.mode = .paused(until: day(1))
        #expect(policy.authorize(files, at: day(0.5)).denial == .paused)
        #expect(policy.authorize(files, at: day(1)).grant != nil)
    }

    @Test func privateModeDeniesAReadAndAsksBeforeALiveRecording() throws {
        let policy = CapturePolicy(mode: .privateMode(until: day(1)), switches: [.files: true, .call: true])
        #expect(policy.authorize(files, at: t0).denial == .privateMode)
        let live = policy.authorize(CaptureRequest(kind: .call, liveSession: true), at: t0)
        let pending = try #require(live.confirmation)
        #expect(live.grant == nil)
        let grant = pending.confirmed(at: t0)
        #expect(grant.kind == .call)
        #expect(grant.expiresAt == t0.addingTimeInterval(CapturePolicy.grantLifetime))
        #expect(policy.authorize(files, at: day(1)).grant != nil)
    }

}

import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct CapturePolicyTests {
    private let files = CaptureRequest(kind: .files, label: "/Users/a/Projects/x.swift")
    private let filesOn = CapturePolicy(switches: [.files: true])

    @Test func everySourceIsOffUntilSwitchedOn() {
        for kind in SourceKind.allCases {
            #expect(CapturePolicy().authorize(CaptureRequest(kind: kind), at: t0).denial == .sourceSwitchedOff)
        }
        #expect(CapturePolicy(switches: [.files: false]).authorize(files, at: t0).grant == nil)
        #expect(filesOn.authorize(files, at: t0).grant?.kind == .files)
    }

    @Test func offModeDeniesEverything() {
        var policy = filesOn
        policy.mode = .off
        #expect(policy.authorize(files, at: t0).denial == .captureOff)
    }

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

    @Test func aDeniedLabelIsDeniedAndAnotherLabelOfTheSameSourceIsAllowed() {
        let policy = CapturePolicy(switches: [.screen: true], denyList: [.screen: ["com.bank"]])
        #expect(policy.authorize(CaptureRequest(kind: .screen, label: "com.bank"), at: t0).denial == .labelDenied)
        #expect(policy.authorize(CaptureRequest(kind: .screen, label: "com.notes"), at: t0).grant != nil)
    }

    @Test func anAllowListAllowsOnlyItsLabels() {
        let policy = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["team"]])
        #expect(policy.authorize(CaptureRequest(kind: .whatsapp, label: "team"), at: t0).grant?.label == "team")
        #expect(policy.authorize(CaptureRequest(kind: .whatsapp, label: "family"), at: t0).denial == .labelNotAllowed)
        #expect(policy.authorize(CaptureRequest(kind: .whatsapp), at: t0).denial == .labelNotAllowed)
    }

    @Test func whatsAppSwitchedOnWithNoListReadsNoChatButASourceWithoutTheRuleReadsAnyLabel() {
        let on = CapturePolicy(switches: [.whatsapp: true, .screen: true])
        #expect(on.authorize(CaptureRequest(kind: .whatsapp, label: "team"), at: t0).denial == .labelNotAllowed)
        #expect(on.authorize(CaptureRequest(kind: .screen, label: "com.notes"), at: t0).grant != nil)
    }
}

import Foundation
import Testing

@testable import WorkbenchCore

struct PresenceReadingTests {
    private func state(_ change: (inout PresenceReading) -> Void) -> PresenceState {
        var reading = PresenceReading()
        change(&reading)
        return reading.state(idleAfter: 120)
    }

    @Test func aPersonAtTheMacIsActiveAndEveryOtherFactMakesThemAway() {
        #expect(state { _ in } == .active)
        #expect(state { $0.idleSeconds = 119 } == .active)
        #expect(state { $0.idleSeconds = 120 } == .idle)
        #expect(state { $0.screenLocked = true } == .locked)
        #expect(state { $0.sessionOnConsole = false } == .locked)
        #expect(state { $0.displayAsleep = true } == .screenOff)
        #expect(state { $0.systemAsleep = true } == .asleep)
    }

    @Test func theMostRestrictiveFactWinsAndALockIsNotUndoneByRecentInput() {
        #expect(
            state {
                $0.screenLocked = true
                $0.idleSeconds = 0
            } == .locked)
        #expect(
            state {
                $0.screenLocked = true
                $0.idleSeconds = 600
            } == .locked)
        #expect(
            state {
                $0.displayAsleep = true
                $0.screenLocked = true
            } == .screenOff)
        #expect(
            state {
                $0.systemAsleep = true
                $0.displayAsleep = true
                $0.screenLocked = true
            } == .asleep)
    }
}

struct ReadAdmissionTests {
    private let screenOn = CapturePolicy(switches: [.screen: true])

    @Test func anAllowedAppIsReadAndEveryOtherAppIsNot() {
        #expect(screenOn.admission(ofApp: "com.apple.Terminal", at: t0).isRead)
        #expect(!screenOn.admission(ofApp: "com.1password.1password", at: t0).isRead)
        #expect(!screenOn.admission(ofApp: "", at: t0).isRead)
        var denying = screenOn
        denying.denyList = [.screen: ["com.apple.Terminal"]]
        #expect(!denying.admission(ofApp: "com.apple.Terminal", at: t0).isRead)
        #expect(denying.admission(ofApp: "com.apple.Notes", at: t0).isRead)
        var listing = screenOn
        listing.allowList = [.screen: ["com.apple.Notes"]]
        #expect(!listing.admission(ofApp: "com.apple.Terminal", at: t0).isRead)
        #expect(listing.admission(ofApp: "com.apple.Notes", at: t0).isRead)
    }

    @Test func anAppThatIsNotReadStillGetsTheBareMarkersAndCaptureThatIsOffGetsNothing() {
        #expect(screenOn.admission(ofApp: "", at: t0).isSkip)
        #expect(screenOn.admission(ofApp: "com.1password.1password", at: t0).isSkip)
        #expect(CapturePolicy(switches: [:]).admission(ofApp: "com.apple.Terminal", at: t0) == .stop)
        #expect(CapturePolicy(mode: .off, switches: [.screen: true]).admission(ofApp: "", at: t0) == .stop)
    }
}

extension ReadAdmission {
    var isRead: Bool { if case .read = self { true } else { false } }
    var isSkip: Bool { if case .skip = self { true } else { false } }
}

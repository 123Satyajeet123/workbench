import AppKit
import CaptureService
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

struct OnboardingTests {

    @Test func lastScreenFinishesOnboarding() {
        let model = OnboardingModel()
        model.advance(to: .done)
        model.next()
        #expect(model.isFinished)
    }

    @Test func everySourceIsOffUntilTheUserTurnsItOn() throws {
        let capture = try captureSettings()
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: Form { SourceToggles() }.environment(capture)))
        window.contentViewController?.view.layoutSubtreeIfNeeded()
        #expect(!capture.isOn(.screen))
        #expect(!capture.isOn(.screenText))
        #expect(!capture.isOn(.files))
        #expect(!capture.isOn(.call))
        capture.set(.call, on: true)
        #expect(capture.isOn(.call))
    }

    @Test func everyScreenSaysOnlyWhatIsTrue() {
        let words = OnboardingScreen.allCases.map { $0.title + " " + $0.lead }.joined(separator: " ")
        for untrue in ["calendar", "research", "deal", "fund"] { #expect(!words.lowercased().contains(untrue)) }
    }
}

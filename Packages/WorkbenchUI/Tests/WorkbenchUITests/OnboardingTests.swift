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
        let pages = SidebarSelection.fixed.map(\.title) + MachineTemplate.all.map(\.name) + ["Settings"]
        let named = words.matches(of: #/(?:Open|in|on the) ([A-Z][a-z]+)/#).map { String($0.1) }
        #expect(!named.isEmpty && named.allSatisfy(pages.contains), "\(named) must be pages that exist")
    }
}

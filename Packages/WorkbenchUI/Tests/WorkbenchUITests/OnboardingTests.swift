import AppKit
import CaptureService
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

struct OnboardingTests {
    @Test func identitySavesAndLoadsWithTrimmedText() throws {
        let store = try scratchStore()
        #expect(try Identity.load(from: store) == nil)
        try Identity(name: "  Rhea Menon \n").save(to: store)
        #expect(try Identity.load(from: store) == Identity(name: "Rhea Menon"))
    }

    @Test func anEditInTheIdentityModelIsSavedAndReloaded() throws {
        let store = try scratchStore()
        let model = IdentityModel(store: store)
        #expect(model.identity == .empty)
        model.identity.name = "Rhea"
        #expect(IdentityModel(store: store).identity == Identity(name: "Rhea"))
    }

    @Test func theNameIsRequiredToContinue() {
        let model = OnboardingModel()
        model.next()
        #expect(model.screen == .you)
        for empty in ["", "   ", "\n"] {
            model.identityModel.identity.name = empty
            #expect(!model.canContinue)
            model.next()
            #expect(model.screen == .you)
        }
        model.identityModel.identity.name = "Rhea"
        #expect(model.canContinue)
        model.next()
        #expect(model.screen == .sources)
    }

    @Test func backWorksOnEveryScreenAfterTheFirst() {
        let model = OnboardingModel()
        model.identityModel.identity.name = "Rhea"
        for _ in 1..<model.screens.count { model.next() }
        for expected in model.screens.dropLast().reversed() {
            model.back()
            #expect(model.screen == expected)
        }
        model.back()
        #expect(model.isFirst)
    }

    @Test func theUserResumesWhereTheyLeftOff() throws {
        let store = try scratchStore()
        let identity = IdentityModel(store: store)
        let model = OnboardingModel(store: store, identity: identity)
        identity.identity.name = "Rhea"
        model.next()
        model.next()
        let resumed = OnboardingModel(store: store, identity: IdentityModel(store: store))
        #expect(resumed.screen == .sources)
        #expect(resumed.identityModel.identity.name == "Rhea")
        #expect(!resumed.isFinished)
    }

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

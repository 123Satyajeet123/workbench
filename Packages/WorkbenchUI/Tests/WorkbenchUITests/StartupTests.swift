import AppKit
import Foundation
import SQLite3
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

struct StartupTests {
    @Test func aWritableFolderStartsTheAppOnAnEmptyStore() throws {
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            Issue.record("the store should open")
            return
        }
        #expect(!session.crew.team.isReady)
        #expect(session.runs.runs.isEmpty)
        #expect(!session.onboarding.isFinished)
        #expect(try session.store.queries.count(of: .activity) == 0)
    }

    @Test func aStoreThatCannotOpenGivesTheCauseAndTheFolder() throws {
        let blocker = scratchFolder()
        try Data().write(to: blocker)
        let folder = blocker.appending(path: "Workbench")
        guard case .failed(let failure) = AppLaunch.start(storeFolder: folder) else {
            Issue.record("the store should not open under a file")
            return
        }
        #expect(failure.storeFolder == folder)
        #expect(!failure.cause.isEmpty)
    }

    @Test func aStoreFromANewerVersionShowsThePlainSentence() throws {
        let store = try scratchStore()
        var handle: OpaquePointer?
        sqlite3_open(store.directory.appending(path: "workbench.sqlite").path, &handle)
        sqlite3_exec(handle, "PRAGMA user_version = 99", nil, nil, nil)
        sqlite3_close(handle)
        guard case .failed(let failure) = AppLaunch.start(storeFolder: store.directory) else {
            Issue.record("the launch should fail")
            return
        }
        #expect(failure.cause == "This store was made by a newer Workbench. Install the newer version.")
    }

    @Test func savedSetupThatCannotBeReadIsShownAndACleanStoreShowsNothing() throws {
        #expect(OnboardingModel(store: try scratchStore()).problem == nil)
        let store = try scratchStore()
        try store.saveState("not json", forKey: "onboarding")
        let model = OnboardingModel(store: store)
        #expect(model.problem == "Workbench could not read your saved setup, so setup starts again.")
        #expect(model.screen == .welcome)
    }

    @Test func aSavedIdentityThatCannotBeReadIsShownOnTheOnboardingScreen() throws {
        let store = try scratchStore()
        try store.saveState("not json", forKey: "identity")
        let identity = IdentityModel(store: store)
        #expect(identity.saveError != nil)
        #expect(OnboardingModel(store: store, identity: identity).problem?.hasPrefix("Your name was not saved") == true)
    }

    @Test func theMainWindowIsNoSmallerThanTheMinimum() throws {
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            Issue.record("the store should open")
            return
        }
        let host = NSHostingController(rootView: WorkbenchView().environment(session))
        #expect(host.sizeThatFits(in: .zero) == WorkbenchView.minimumSize)
    }

    @Test func closingTheLastWindowKeepsTheAppRunning() {
        let delegate = AppDelegate(storeFolder: scratchFolder())
        #expect(!delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @Test func makingADelegateOpensNoStoreUntilTheAppAsksForIt() {
        let folder = scratchFolder()
        let delegate = AppDelegate(storeFolder: folder)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        guard case .ready = delegate.launch else {
            Issue.record("the launch should succeed")
            return
        }
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "workbench.sqlite").path))
    }
}

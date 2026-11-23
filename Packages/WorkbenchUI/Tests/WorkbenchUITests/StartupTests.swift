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
        #expect(session.crew.machines.isEmpty, "the machines are made when onboarding finishes")
        #expect(session.runs.runs.isEmpty)
        #expect(!session.onboarding.isFinished)
        #expect(try session.store.queries.count(of: .activity) == 0)
    }

    private func launch(_ folder: URL) throws -> AppSession {
        guard case .ready(let session) = AppLaunch.start(storeFolder: folder) else {
            throw CocoaError(.fileReadUnknown)
        }
        return session
    }

    @Test(arguments: [TeamTemplate.fund, .startupTeam]) func aNewStoreHoldsExactlyTheMachinesOfTheChosenTemplate(
        template: TeamTemplate
    ) throws {
        let session = try launch(scratchFolder())
        session.team.template = template
        session.onboarding.advance(to: .done)
        session.onboarding.next()
        let expected = template.seeds.map(\.name)
        #expect(try session.store.queries.machines().map(\.name) == expected)
        #expect(session.crew.machines.map(\.name) == expected)
    }

    @Test func anExistingStoreIsTheSameAfterALaunch() throws {
        let folder = scratchFolder()
        do {
            let store = try Store(directory: folder)
            try store.seedMachines([(.team, "Pip")])
        }
        let session = try launch(folder)
        #expect(try session.store.queries.machines().map(\.name) == ["Pip"])
        #expect(!session.onboarding.startsTeam)
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

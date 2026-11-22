import Foundation
import Testing

@testable import WorkbenchUI

/// Two app copies on one data folder: the second does not open the store.
@MainActor @Suite struct OneAppTests {
    @Test func aSecondCopyOnTheSameFolderFailsWithTheAlreadyOpenText() throws {
        let folder = scratchFolder()
        let first = AppLaunch.start(storeFolder: folder)
        defer { withExtendedLifetime(first) {} }
        guard case .ready = first else {
            Issue.record("the first copy did not start")
            return
        }
        guard case .failed(let failure) = AppLaunch.start(storeFolder: folder) else {
            Issue.record("a second copy started on the same folder")
            return
        }
        #expect(failure.cause == "Workbench is already open. Only one copy can keep your data.")
    }
}

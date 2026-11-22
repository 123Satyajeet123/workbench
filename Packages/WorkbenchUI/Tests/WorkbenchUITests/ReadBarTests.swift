import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

@MainActor struct ReadBarTests {
    @Test func manyViewsStillFitANarrowPage() throws {
        guard case .ready(let session) = AppLaunch.start(storeFolder: scratchFolder()) else {
            Issue.record("the app did not start")
            return
        }
        let id = try #require(session.crew.create(from: .team, name: "Pip"))
        let pip = try #require(session.crew.helper(id: id))
        #expect(pip.spec.views.count > 4)
        let bar = NSHostingController(rootView: ReadBar(model: pip).environment(session))
        #expect(bar.sizeThatFits(in: CGSize(width: 420, height: 200)).width <= 420)
    }
}

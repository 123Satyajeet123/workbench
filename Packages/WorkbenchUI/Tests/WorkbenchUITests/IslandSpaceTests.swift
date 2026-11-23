import AppKit
import Testing

@testable import WorkbenchUI

/// A Space change slides a window that belongs to a Space. The island stays still because a space of its own holds it.
@MainActor @Suite struct IslandSpaceTests {
    @Test func thisMacOSHasTheSpaceTheIslandNeeds() {
        #expect(IslandSpace() != nil)
    }

    @Test func theIslandKeepsItsPublicSpaceBehaviourForTheDayThePrivateSpaceIsGone() {
        let panel = IslandPanel(state: { .idle }, open: {})
        #expect(panel.collectionBehavior.isSuperset(of: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]))
    }

    @Test func theIslandIsHandedToTheSpaceOnlyWhereItShows() {
        let space = SpaceSpy()
        let panel = IslandPanel(state: { .idle }, open: {}, space: space)
        let shows = IslandMetrics.screen != nil
        #expect(space.held.count == (shows ? 1 : 0))
        #expect(space.held.allSatisfy { $0 === panel })
    }
}

private final class SpaceSpy: SpaceHolding {
    private(set) var held: [NSWindow] = []

    func hold(_ window: NSWindow) { held.append(window) }
}

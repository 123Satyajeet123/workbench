import Testing

@testable import WorkbenchUI

@Suite struct PageTabsTests {
    @Test func eachTabGoesItsOwnWayAndKeepsItsOwnHistory() {
        var tabs = PageTabs()
        #expect(tabs.page == .mochi && tabs.tabs.count == 1)
        tabs.open(.people)
        tabs.openNewTab()
        #expect(tabs.tabs.count == 2 && tabs.page == .mochi && !tabs.canGoBack)
        tabs.open(.usage)
        tabs.select(tabs.tabs[0].id)
        #expect(tabs.page == .people && tabs.canGoBack)
        tabs.goBack()
        #expect(tabs.page == .mochi && tabs.canGoForward)
        tabs.select(tabs.tabs[1].id)
        #expect(tabs.page == .usage)
    }

    @Test func openingTheSamePageAgainIsNotAStep() {
        var tabs = PageTabs()
        tabs.open(.mochi)
        #expect(!tabs.canGoBack)
    }

    @Test func closingATabShowsItsNeighbourAndTheLastTabStays() {
        var tabs = PageTabs()
        tabs.openNewTab(.people)
        tabs.openNewTab(.usage)
        tabs.close(tabs.tabs[2].id)
        #expect(tabs.page == .people && tabs.tabs.count == 2)
        tabs.select(tabs.tabs[0].id)
        tabs.close(tabs.tabs[0].id)
        #expect(tabs.page == .people && tabs.tabs.count == 1)
        tabs.close(tabs.tabs[0].id)
        #expect(tabs.tabs.count == 1 && !tabs.canClose)
    }

    @Test func draggingATabByWholeTabWidthsMovesItThatFarAndKeepsTheOpenTab() {
        var tabs = PageTabs()
        tabs.openNewTab(.people)
        tabs.openNewTab(.usage)
        let usage = tabs.selected
        tabs.move(usage, by: -2)
        #expect(tabs.tabs.map(\.page) == [.usage, .mochi, .people] && tabs.page == .usage)
        tabs.move(usage, by: 9)
        #expect(tabs.tabs.map(\.page) == [.mochi, .people, .usage] && tabs.selected == usage)
        tabs.move(usage, by: 0)
        #expect(tabs.tabs.map(\.page) == [.mochi, .people, .usage])
    }

    @Test func nextAndPreviousTabWrapAround() {
        var tabs = PageTabs()
        tabs.openNewTab(.people)
        tabs.selectNext()
        #expect(tabs.page == .mochi)
        tabs.selectPrevious()
        #expect(tabs.page == .people)
    }

    @Test func tabsSurviveARestartAndAPageThatIsGoneBecomesToday() {
        var tabs = PageTabs()
        tabs.open(.machine(7))
        tabs.openNewTab(.usage)
        tabs.openNewTab(.timeline)
        tabs.select(tabs.tabs[1].id)
        let restored = PageTabs(saved: tabs.saved) { $0 != .machine(7) }
        #expect(restored.tabs.map(\.page) == [.mochi, .usage, .timeline] && restored.page == .usage)
        #expect(PageTabs(saved: "nonsense").tabs.map(\.page) == [.mochi])
    }
}

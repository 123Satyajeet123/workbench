import Testing

@testable import WorkbenchUI

@Suite struct PageTabsTests {
    @Test func eachTabGoesItsOwnWayAndKeepsItsOwnHistory() {
        var tabs = PageTabs()
        #expect(tabs.page == .day && tabs.tabs.count == 1)
        tabs.open(.people)
        tabs.openNewTab()
        #expect(tabs.tabs.count == 2 && tabs.page == .day && !tabs.canGoBack)
        tabs.open(.usage)
        tabs.select(tabs.tabs[0].id)
        #expect(tabs.page == .people && tabs.canGoBack)
        tabs.goBack()
        #expect(tabs.page == .day && tabs.canGoForward)
        tabs.select(tabs.tabs[1].id)
        #expect(tabs.page == .usage)
    }

    @Test func openingTheSamePageAgainIsNotAStep() {
        var tabs = PageTabs()
        tabs.open(.day)
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
        #expect(tabs.tabs.map(\.page) == [.usage, .day, .people] && tabs.page == .usage)
        tabs.move(usage, by: 9)
        #expect(tabs.tabs.map(\.page) == [.day, .people, .usage] && tabs.selected == usage)
        tabs.move(usage, by: 0)
        #expect(tabs.tabs.map(\.page) == [.day, .people, .usage])
    }

    @Test func nextAndPreviousTabWrapAround() {
        var tabs = PageTabs()
        tabs.openNewTab(.people)
        tabs.selectNext()
        #expect(tabs.page == .day)
        tabs.selectPrevious()
        #expect(tabs.page == .people)
    }

    @Test func tabsSurviveARestartAndAPageThatIsGoneBecomesToday() {
        var tabs = PageTabs()
        tabs.open(.machine(7))
        tabs.openNewTab(.usage)
        tabs.openNewTab(.review)
        tabs.select(tabs.tabs[1].id)
        let restored = PageTabs(saved: tabs.saved) { $0 != .machine(7) }
        #expect(restored.tabs.map(\.page) == [.day, .usage, .review] && restored.page == .usage)
        #expect(PageTabs(saved: "nonsense").tabs.map(\.page) == [.day])
    }
}

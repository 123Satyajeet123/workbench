import Testing

@testable import WorkbenchUI

@Suite struct SidebarSelectionTests {
    @Test func everyFixedPageSurvivesItsRawValueAndItsLink() {
        for page in SidebarSelection.fixed + [.machine(7)] {
            #expect(SidebarSelection(rawValue: page.rawValue) == page)
            #expect(SidebarSelection(url: page.url) == page)
        }
    }

    @Test func theHomeKeepsItsOldRawValueAndIsCalledToday() {
        #expect(SidebarSelection(rawValue: "day") == .day && SidebarSelection.day.title == "Today")
        #expect(SidebarSelection.fixed.prefix(3).map(\.title) == ["Today", "People", "Projects"])
    }

    @Test func aPageThatDoesNotExistIsNotOne() {
        #expect(SidebarSelection(rawValue: "yesterday") == nil)
    }
}

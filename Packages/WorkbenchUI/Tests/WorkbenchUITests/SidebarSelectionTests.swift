import Foundation
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

    @Test func theOldRunsAndAdvancedLinksOpenUsageAndCrewIsAPage() throws {
        #expect(SidebarSelection(url: try #require(URL(string: "workbench://open?page=runs"))) == .usage)
        #expect(SidebarSelection(rawValue: "advanced") == .usage)
        #expect(SidebarSelection(rawValue: "crew") == .crew && SidebarSelection.crew.title == "Crew")
    }

    @Test func settingsIsAPageAndAskingForCaptureSettingsOpensItOnCapture() {
        #expect(SidebarSelection(rawValue: "settings") == .settings && SidebarSelection.settings.title == "Settings")
        let navigation = Navigation()
        navigation.openSettings(.capture)
        #expect(navigation.requested == .settings && navigation.settingsSection == .capture)
    }

    @Test func aPageThatDoesNotExistIsNotOne() {
        #expect(SidebarSelection(rawValue: "yesterday") == nil)
    }
}

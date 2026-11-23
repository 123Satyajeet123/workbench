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

    @Test func theHomeIsMochiAndOldTodayAndReviewLinksOpenIt() {
        #expect(SidebarSelection(rawValue: "day") == .mochi && SidebarSelection(rawValue: "review") == .mochi)
        #expect(SidebarSelection.fixed.prefix(3).map(\.title) == ["Mochi", "People", "Projects"])
        #expect(SidebarSelection.calls.title == "Calls" && SidebarSelection.crew.title == "Overview")
    }

    @Test func theOldRunsAndAdvancedLinksOpenUsageAndCrewIsAPage() throws {
        #expect(SidebarSelection(url: try #require(URL(string: "workbench://open?page=runs"))) == .usage)
        #expect(SidebarSelection(rawValue: "advanced") == .usage)
        #expect(SidebarSelection(rawValue: "crew") == .crew && SidebarSelection.crew.title == "Overview")
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

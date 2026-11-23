import Testing

@testable import WorkbenchUI

struct SidebarLayoutTests {
    @Test func everyPageOfTheWindowButUsageAndSettingsIsInTheSidebarOnceInItsOrder() {
        let pages = SidebarLayout.pages
        #expect(pages == [.day, .people, .projects, .calls, .deals, .mochi, .crew, .review, .catalog])
        let windowPages = SidebarSelection.fixed.filter { ![.usage, .settings].contains($0) }
        #expect(Set(pages) == Set(windowPages) && pages.count == windowPages.count)
    }

    @Test func everyHelperInTheSidebarHasAFaceAndMochiWearsItsCrown() {
        for case .helper(let page) in SidebarLayout.sections.flatMap(\.entries) {
            #expect(page.look != nil, "\(page) has no face")
        }
        #expect(SidebarSelection.mochi.look == Mascot.Look(hue: 0.04, wear: .crown))
    }
}

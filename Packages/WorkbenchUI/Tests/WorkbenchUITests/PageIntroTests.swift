import Testing

@testable import WorkbenchUI

struct PageIntroTests {
    @Test func aClosedNoteStaysClosedAcrossLaunchesAndOpensAgain() throws {
        var dismissed = DismissedIntros()
        #expect(!dismissed.contains(.day) && !dismissed.contains(.people))
        dismissed.dismiss(.people)
        dismissed.dismiss(.machine(12))
        let saved = try #require(DismissedIntros(rawValue: dismissed.rawValue))
        #expect(saved == dismissed)
        #expect(saved.contains(.people) && saved.contains(.machine(12)) && !saved.contains(.day))
        var restored = saved
        restored.restore(.people)
        #expect(!restored.contains(.people) && restored.contains(.machine(12)))
    }

    @Test func nothingIsClosedOnTheFirstLaunch() throws {
        let fresh = try #require(DismissedIntros(rawValue: ""))
        #expect(fresh.pages.isEmpty)
    }

    @Test func everySidebarPageHasANoteAndOtherPagesHaveNone() {
        for case .page(let page, _) in SidebarLayout.sections.flatMap(\.entries) {
            #expect(page.intro?.isEmpty == false, "\(page) has no note")
        }
        for case .helper(let page) in SidebarLayout.sections.flatMap(\.entries) {
            #expect(page.intro?.isEmpty == false, "\(page) has no note")
        }
        #expect(SidebarSelection.advanced.intro == nil && SidebarSelection.machine(1).intro == nil)
    }
}

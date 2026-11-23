import Testing

@testable import WorkbenchUI

struct SidebarLayoutTests {
    private var pages: [SidebarSelection] {
        SidebarLayout.sections.flatMap(\.entries).compactMap { entry in
            switch entry {
            case .page(let page, _), .helper(let page): page
            case .machines: nil
            }
        }
    }

    @Test func everyPageOfTheWindowButUsageAndSettingsIsInTheSidebarOnceInItsOrder() {
        #expect(pages == [.day, .people, .projects, .calls, .deals, .mochi, .crew, .review, .catalog])
        let windowPages = SidebarSelection.fixed.filter { ![.usage, .settings].contains($0) }
        #expect(Set(pages) == Set(windowPages) && pages.count == windowPages.count)
    }

    @Test func aSavedPageWithNoRowIsNotListedSoTheWindowFallsBackToToday() {
        #expect(SidebarLayout.lists(.deals) && SidebarLayout.lists(.catalog))
        #expect(SidebarLayout.lists(.day) && SidebarLayout.lists(.calls) && SidebarLayout.lists(.machine(7)))
        #expect(SidebarLayout.lists(.usage), "Usage has its own row above Settings")
        #expect(SidebarLayout.lists(.settings), "Settings has its own row at the bottom")
    }

    @Test func machinesSitInTheCrewSectionBetweenCrewAndReview() throws {
        let crew = try #require(SidebarLayout.sections.first { $0.title == "Crew" })
        let machines = try #require(crew.entries.firstIndex(of: .machines))
        #expect(crew.entries[machines - 1] == .page(.crew, symbol: "rectangle.grid.2x2"))
        #expect(crew.entries[machines + 1] == .page(.review, symbol: "checkmark.circle"))
        #expect(SidebarLayout.sections.filter { $0.entries.contains(.machines) }.count == 1)
    }

    @Test func everyHelperInTheSidebarHasAFaceAndMochiWearsItsCrown() {
        for case .helper(let page) in SidebarLayout.sections.flatMap(\.entries) {
            #expect(page.look != nil, "\(page) has no face")
        }
        #expect(SidebarSelection.mochi.look == Mascot.Look(hue: 0.04, wear: .crown))
    }
}

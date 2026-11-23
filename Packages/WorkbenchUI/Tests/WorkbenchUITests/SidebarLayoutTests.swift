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

    @Test func everyPageOfTheWindowButDealsAndTeamIsInTheSidebarOnceInItsOrder() {
        #expect(pages == [.mochi, .people, .projects, .calls, .timeline, .crew])
        let windowPages = SidebarSelection.fixed.filter { ![.deals, .catalog, .usage, .settings].contains($0) }
        #expect(Set(pages) == Set(windowPages) && pages.count == windowPages.count)
    }

    @Test func aSavedPageWithNoRowIsNotListedSoTheWindowFallsBackToMochi() {
        #expect(!SidebarLayout.lists(.deals) && !SidebarLayout.lists(.catalog))
        for page in [SidebarSelection.mochi, .timeline, .calls, .machine(7)] { #expect(SidebarLayout.lists(page)) }
        #expect(SidebarLayout.lists(.usage), "Usage has its own row above Settings")
        #expect(SidebarLayout.lists(.settings), "Settings has its own row at the bottom")
    }

    @Test func machinesSitUnderMochisCrewAfterTheOverview() throws {
        let crew = try #require(SidebarLayout.sections.first { $0.title == "Mochi's crew" })
        #expect(crew.entries == [.page(.crew, symbol: "rectangle.grid.2x2"), .machines])
        #expect(SidebarLayout.sections.first?.entries.first == .helper(.mochi), "Mochi is the home, listed first")
        #expect(SidebarLayout.sections.filter { $0.entries.contains(.machines) }.count == 1)
    }

    @Test func everyHelperInTheSidebarHasAFaceAndMochiWearsItsCrown() {
        for case .helper(let page) in SidebarLayout.sections.flatMap(\.entries) {
            #expect(page.look != nil, "\(page) has no face")
        }
        #expect(SidebarSelection.mochi.look == Mascot.Look(hue: 0.04, wear: .crown))
    }
}

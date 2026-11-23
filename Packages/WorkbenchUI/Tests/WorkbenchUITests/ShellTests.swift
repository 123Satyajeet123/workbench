import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

private func machine(_ id: Int64, _ name: String = "Pip", status: MachineStatus = .idle) -> SidebarMachine {
    SidebarMachine(id: id, name: name, status: status)
}

private func sections(
    _ template: TeamTemplate = .fund, machines: [SidebarMachine] = [], today: Int = 0, checks: Int = 0
) -> [SidebarSection] {
    SidebarPlan.sections(template: template, machines: machines, today: today, checks: checks)
}

private func pages(_ sections: [SidebarSection]) -> [SidebarSelection] {
    sections.flatMap(\.rows).compactMap { if case .page(let page, _) = $0 { page } else { nil } }
}

/// The sidebar is one fixed order, from one function.
struct SidebarPlanTests {
    @Test func theOrderIsFixedAndTodayIsFirst() {
        let all = sections(machines: [machine(1), machine(2)])
        #expect(pages(all) == [.day, .review, .people, .projects, .calls, .deals, .catalog])
        #expect(all.flatMap(\.rows).first?.selection == .day)
        #expect(all.map(\.header) == [nil, "Machines", nil])
        #expect(all[1].rows.map(\.selection) == [.machine(1), .machine(2)])
        #expect(all.last?.rows.map(\.selection) == [.catalog])
    }

    @Test(arguments: [(TeamTemplate.fund, true), (.startupTeam, false), (.blank, false)])
    func dealsShowOnlyWhenTheTemplateHasADealType(template: TeamTemplate, hasDeals: Bool) {
        #expect(pages(sections(template)).contains(.deals) == hasDeals)
        #expect(template.objectTypes.contains { $0.id == "deal" } == hasDeals)
    }

    @Test(arguments: [0, 1, 5]) func oneRowPerMachineAndTheRestDoesNotMove(count: Int) {
        let machines = (1...max(count, 1)).prefix(count).map { machine(Int64($0), "M\($0)") }
        let all = sections(machines: Array(machines))
        #expect(all[1].rows.count == count && all[1].header == "Machines")
        #expect(pages(all) == pages(sections()))
    }

    @Test func todayAndChecksCarryTheirCountsAndNoOtherPageDoes() {
        let rows = sections(today: 4, checks: 9).flatMap(\.rows)
        #expect(rows.first == .page(.day, count: 4) && rows[1] == .page(.review, count: 9))
        for row in rows.dropFirst(2) { #expect(row == .page(row.selection, count: 0)) }
    }

    @Test func aRowHasPlainWordsAndNoFace() {
        let titles = pages(sections()).map(\.title)
        #expect(titles == ["Today", "Checks", "People", "Projects", "Calls", "Deals", "Team"])
        for page in pages(sections()) { #expect(!page.symbol.isEmpty) }
    }

    @Test func aSavedPageNoRowListsGivesWayToToday() {
        let noDeals = sections(.startupTeam, machines: [machine(7)])
        #expect(SidebarPlan.landing(.deals, in: noDeals) == .day)
        #expect(SidebarPlan.landing(.machine(8), in: noDeals) == .day)
        #expect(SidebarPlan.landing(.advanced, in: noDeals) == .day)
        #expect(SidebarPlan.landing(.machine(7), in: noDeals) == .machine(7))
        #expect(SidebarPlan.landing(.deals, in: sections(.fund)) == .deals)
        #expect(SidebarPlan.landing(.catalog, in: noDeals) == .catalog)
    }

    @Test func mochiAndTheCrewPageStayReachableWithNoRow() {
        for page in [SidebarSelection.mochi, .crew] {
            #expect(!pages(sections()).contains(page))
            #expect(SidebarPlan.landing(page, in: sections()) == page)
        }
    }

    @Test func aMachineShowsOneStatusAndReadingBeatsNeedsYou() {
        #expect(MachineStatus(isReading: true, needsYou: true) == .reading)
        #expect(MachineStatus(isReading: false, needsYou: true) == .needsYou)
        #expect(MachineStatus(isReading: false, needsYou: false) == .idle)
    }
}

struct PanelTests {
    @Test func aFactWinsThenThePlaybookThenNothing() {
        #expect(PanelContent.of(hasFact: true, hasPlaybook: true, isOn: false) == .fact)
        #expect(PanelContent.of(hasFact: false, hasPlaybook: true, isOn: true) == .playbook)
        #expect(PanelContent.of(hasFact: false, hasPlaybook: true, isOn: false) == .hidden)
        #expect(PanelContent.of(hasFact: false, hasPlaybook: false, isOn: true) == .hidden)
    }

    @Test func theSwitchClosesAFactFirstAndOtherwiseFlips() {
        var panel = PanelSwitch()
        var closed = 0
        panel.toggle(hasFact: true) { closed += 1 }
        #expect(closed == 1 && panel.isOn)
        panel.toggle(hasFact: false) { closed += 1 }
        #expect(closed == 1 && !panel.isOn)
        panel.toggle(hasFact: false) { closed += 1 }
        #expect(panel.isOn)
    }

    @Test func aPageThatClosesCannotTakeDownThePageThatOpens() {
        let slot = PlaybookSlot()
        let first = UUID()
        let second = UUID()
        #expect(!slot.hasContent)
        slot.set({ AnyView(EmptyView()) }, by: first)
        slot.set({ AnyView(EmptyView()) }, by: second)
        slot.clear(by: first)
        #expect(slot.hasContent)
        slot.clear(by: second)
        #expect(!slot.hasContent)
    }

    @Test func theSurfaceFollowsThePage() {
        #expect(Surface(page: .day) == .today && Surface(page: .people) == .today)
        #expect(Surface(page: .review) == .review && Surface(page: .machine(3)) == .machinePage)
    }

    @Test func aRequestedFactIsFoundByItsIdOrNotAtAll() {
        let facts: [TitledItem] = [(FactFixture.item(4), "Ship"), (FactFixture.item(9), "Pay")]
        #expect(ShellFacts.item(9, in: facts)?.id == 9)
        #expect(ShellFacts.item(5, in: facts) == nil)
    }
}

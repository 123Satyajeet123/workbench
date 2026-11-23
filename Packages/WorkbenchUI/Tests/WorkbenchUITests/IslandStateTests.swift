import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct IslandStateTests {
    private let since = Date(timeIntervalSince1970: 1_790_000_000)
    private let atlas = (name: "Atlas", page: SidebarSelection.machine(4))
    private let pip = (name: "Pip", page: SidebarSelection.machine(7))
    private let plan = PlanLimits.Window(used: 0.42, resetsAt: nil, isAtLimit: false)

    @Test func aRecordingComesFirstThenAReadingThenTheQueueThenThePlan() {
        #expect(
            IslandState(recordingSince: since, reading: [atlas], waiting: ["Pip"], plan: plan)
                == .recording(since: since))
        #expect(
            IslandState(recordingSince: nil, reading: [atlas], waiting: ["Pip"], plan: plan)
                == .reading(names: ["Atlas"], page: .machine(4)))
        #expect(
            IslandState(recordingSince: nil, reading: [atlas, pip], waiting: [])
                == .reading(names: ["Atlas", "Pip"], page: .crew))
        #expect(
            IslandState(recordingSince: nil, reading: [], waiting: ["Pip", "Pip"], plan: plan)
                == .waiting(machines: ["Pip", "Pip"]))
        #expect(IslandState(recordingSince: nil, reading: [], waiting: [], plan: plan) == .plan(plan))
        #expect(IslandState(recordingSince: nil, reading: [], waiting: []) == .idle)
    }

    @Test func aCallToRecordComesAfterARecordingAndBeforeEverythingElse() {
        #expect(
            IslandState(recordingSince: since, offering: "Zoom", reading: [atlas], waiting: [])
                == .recording(since: since))
        let offered = IslandState(recordingSince: nil, offering: "Zoom", reading: [atlas], waiting: ["Pip"])
        #expect(offered == .offer("Zoom") && offered.page == .calls && offered.detail == "Zoom call")
        #expect(
            IslandState(
                recordingSince: nil, offering: "Zoom", reading: [atlas], waiting: [],
                shows: IslandShows(recording: false)) == .reading(names: ["Atlas"], page: .machine(4)))
    }

    @Test func whatTheFounderSwitchedOffIsSkipped() {
        let quiet = IslandShows(recording: false, reading: false, review: true)
        #expect(
            IslandState(recordingSince: since, reading: [atlas], waiting: ["Pip"], shows: quiet)
                == .waiting(machines: ["Pip"]))
        let none = IslandShows(recording: false, reading: false, review: false)
        #expect(IslandState(recordingSince: since, reading: [atlas], waiting: ["Pip"], shows: none) == .idle)
    }

    @Test func pressingOpensThePageBehindWhatIsShown() {
        #expect(IslandState.recording(since: since).page == .calls)
        #expect(IslandState.reading(names: ["Atlas"], page: .machine(4)).page == .machine(4))
        #expect(IslandState.waiting(machines: ["Pip"]).page == .mochi)
        #expect(IslandState.plan(plan).page == .usage)
        #expect(IslandState.idle.page == nil)
    }

    @Test func hoveringSaysOneMoreLine() {
        #expect(IslandState.recording(since: since).detail == "Recording a call")
        #expect(IslandState.reading(names: ["Atlas"], page: .machine(4)).detail == "Atlas is reading")
        #expect(IslandState.reading(names: ["Atlas", "Pip"], page: .crew).detail == "Atlas and Pip are reading")
        #expect(IslandState.waiting(machines: ["Pip"]).detail == "Pip asks: is this right?")
        #expect(
            IslandState.waiting(machines: ["Relay", "Pip", "Pip", "Relay", "Pip"]).detail
                == "5 to review · Pip 3, Relay 2")
        #expect(IslandState.plan(plan).detail == "Claude plan · 42%")
    }
}

@Suite struct IslandMetricsTests {
    @Test func aScreenWithoutANotchGetsASlimPillThatOnlyHoldsTheEars() {
        let metrics = IslandMetrics(screen: nil)
        #expect(!metrics.hasNotch)
        #expect(metrics.compactSize(ear: 0).width == metrics.notchWidth + 2 * IslandMetrics.minEar)
        #expect(metrics.compactSize(ear: 500).width == metrics.notchWidth + 2 * IslandMetrics.maxEar)
        #expect(metrics.compactSize.width < IslandMetrics.defaultNotch.width)
        #expect(metrics.expandedSize.width >= metrics.compactSize.width)
        #expect(metrics.panelSize.width > metrics.expandedSize.width)
        #expect(metrics.panelSize(expanded: true).height > metrics.expandedSize.height)
        #expect(metrics.panelSize(expanded: false).height == metrics.notchHeight + metrics.top)
    }

    @Test func aLongMachineNameIsShortenedToFitBesideTheCamera() {
        #expect(IslandView.short("Pip") == "Pip")
        #expect(IslandView.short("Sentinel") == "Sentinel")
        #expect(IslandView.short("Investor updates") == "Investor…")
    }
}

@Suite struct PageLinkTests {
    @Test func everyPageHasALinkThatOpensItAndAForeignLinkOpensNothing() {
        for page in SidebarSelection.fixed + [.machine(42)] {
            #expect(SidebarSelection(url: page.url) == page)
        }
        #expect(SidebarSelection.timeline.url.absoluteString == "workbench://open?page=timeline")
        #expect(SidebarSelection(url: URL(string: "https://open?page=review")!) == nil)
        #expect(SidebarSelection(url: URL(string: "workbench://delete?page=review")!) == nil)
        #expect(SidebarSelection(url: URL(string: "workbench://open?page=nothing")!) == nil)
    }
}

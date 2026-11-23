import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct NotchStateTests {
    private let since = Date(timeIntervalSince1970: 1_790_000_000)
    private let atlas = (name: "Atlas", page: SidebarSelection.machine(4))
    private let pip = (name: "Pip", page: SidebarSelection.machine(7))
    private let plan = PlanLimits.Window(used: 0.42, resetsAt: nil, isAtLimit: false)

    @Test func aRecordingComesFirstThenAReadingThenTheQueueThenThePlan() {
        #expect(
            NotchState(recordingSince: since, reading: [atlas], waiting: ["Pip"], plan: plan)
                == .recording(since: since))
        #expect(
            NotchState(recordingSince: nil, reading: [atlas], waiting: ["Pip"], plan: plan)
                == .reading(names: ["Atlas"], page: .machine(4)))
        #expect(
            NotchState(recordingSince: nil, reading: [atlas, pip], waiting: [])
                == .reading(names: ["Atlas", "Pip"], page: .crew))
        #expect(
            NotchState(recordingSince: nil, reading: [], waiting: ["Pip", "Pip"], plan: plan)
                == .waiting(machines: ["Pip", "Pip"]))
        #expect(NotchState(recordingSince: nil, reading: [], waiting: [], plan: plan) == .plan(plan))
        #expect(NotchState(recordingSince: nil, reading: [], waiting: []) == .idle)
    }

    @Test func whatTheFounderSwitchedOffIsSkipped() {
        let quiet = NotchShows(recording: false, reading: false, review: true)
        #expect(
            NotchState(recordingSince: since, reading: [atlas], waiting: ["Pip"], shows: quiet)
                == .waiting(machines: ["Pip"]))
        let none = NotchShows(recording: false, reading: false, review: false)
        #expect(NotchState(recordingSince: since, reading: [atlas], waiting: ["Pip"], shows: none) == .idle)
    }

    @Test func pressingOpensThePageBehindWhatIsShown() {
        #expect(NotchState.recording(since: since).page == .calls)
        #expect(NotchState.reading(names: ["Atlas"], page: .machine(4)).page == .machine(4))
        #expect(NotchState.waiting(machines: ["Pip"]).page == .review)
        #expect(NotchState.plan(plan).page == .usage)
        #expect(NotchState.idle.page == nil)
    }

    @Test func hoveringSaysOneMoreLine() {
        #expect(NotchState.recording(since: since).detail == "Recording a call")
        #expect(NotchState.reading(names: ["Atlas"], page: .machine(4)).detail == "Atlas is reading")
        #expect(NotchState.reading(names: ["Atlas", "Pip"], page: .crew).detail == "Atlas and Pip are reading")
        #expect(NotchState.waiting(machines: ["Pip"]).detail == "1 to review from Pip")
        #expect(
            NotchState.waiting(machines: ["Relay", "Pip", "Pip", "Relay", "Pip"]).detail
                == "5 to review · Pip 3, Relay 2")
        #expect(NotchState.plan(plan).detail == "Claude plan · 42%")
    }
}

@Suite struct NotchMetricsTests {
    @Test func aScreenWithoutANotchGetsASlimPillThatOnlyHoldsTheEars() {
        let metrics = NotchMetrics(screen: nil)
        #expect(!metrics.hasNotch)
        #expect(metrics.compactSize(ear: 0).width == metrics.notchWidth + 2 * NotchMetrics.minEar)
        #expect(metrics.compactSize(ear: 500).width == metrics.notchWidth + 2 * NotchMetrics.maxEar)
        #expect(metrics.compactSize.width < NotchMetrics.defaultNotch.width)
        #expect(metrics.expandedSize.width >= metrics.compactSize.width)
        #expect(metrics.panelSize.width > metrics.expandedSize.width)
        #expect(metrics.panelSize(expanded: true).height > metrics.expandedSize.height)
        #expect(metrics.panelSize(expanded: false).height == metrics.notchHeight + metrics.top)
    }

    @Test func aLongMachineNameIsShortenedToFitBesideTheCamera() {
        #expect(NotchView.short("Pip") == "Pip")
        #expect(NotchView.short("Sentinel") == "Sentinel")
        #expect(NotchView.short("Investor updates") == "Investor…")
    }
}

@Suite struct PageLinkTests {
    @Test func everyPageHasALinkThatOpensItAndAForeignLinkOpensNothing() {
        for page in SidebarSelection.fixed + [.machine(42)] {
            #expect(SidebarSelection(url: page.url) == page)
        }
        #expect(SidebarSelection.review.url.absoluteString == "workbench://open?page=review")
        #expect(SidebarSelection(url: URL(string: "https://open?page=review")!) == nil)
        #expect(SidebarSelection(url: URL(string: "workbench://delete?page=review")!) == nil)
        #expect(SidebarSelection(url: URL(string: "workbench://open?page=nothing")!) == nil)
    }
}

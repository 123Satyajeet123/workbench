import AppKit
import Foundation
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The island shows one thing at a time: a recording first, then a reading machine, then what needs the person, then
/// the plan.
@Suite struct IslandStateTests {
    private let since = Date(timeIntervalSince1970: 1_790_000_000)
    private let atlas = (name: "Atlas", page: SidebarSelection.machine(4))
    private let pip = (name: "Pip", page: SidebarSelection.machine(7))
    private let plan = PlanLimits.Window(used: 0.42, resetsAt: nil, isAtLimit: false)
    private let everything = IslandShows(plan: true)

    @Test func aRecordingComesFirstThenAReadingThenWhatNeedsYouThenThePlan() {
        #expect(
            IslandState(recordingSince: since, reading: [atlas], needsYou: ["Pip"], plan: plan, shows: everything)
                == .recording(since: since))
        #expect(
            IslandState(recordingSince: nil, reading: [atlas], needsYou: ["Pip"], plan: plan, shows: everything)
                == .reading(names: ["Atlas"], page: .machine(4)))
        #expect(
            IslandState(recordingSince: nil, reading: [atlas, pip], needsYou: [])
                == .reading(names: ["Atlas", "Pip"], page: .crew))
        #expect(
            IslandState(recordingSince: nil, reading: [], needsYou: ["Pip", "Pip"], plan: plan, shows: everything)
                == .needsYou(machines: ["Pip", "Pip"]))
        #expect(
            IslandState(recordingSince: nil, reading: [], needsYou: [], plan: plan, shows: everything) == .plan(plan))
        #expect(IslandState(recordingSince: nil, reading: [], needsYou: []) == .idle)
    }

    @Test func whatTheFounderSwitchedOffIsSkipped() {
        let quiet = IslandShows(recording: false, reading: false, needsYou: true)
        #expect(
            IslandState(recordingSince: since, reading: [atlas], needsYou: ["Pip"], shows: quiet)
                == .needsYou(machines: ["Pip"]))
        let none = IslandShows(recording: false, reading: false, needsYou: false)
        #expect(
            IslandState(recordingSince: since, reading: [atlas], needsYou: ["Pip"], plan: plan, shows: none) == .idle)
    }

    @Test func aReadingThatEndsWhileACallRecordsChangesNothing() {
        let recording = IslandState(recordingSince: since, reading: [atlas], needsYou: [])
        #expect(recording == IslandState(recordingSince: since, reading: [], needsYou: []))
    }

    @Test func aClickOpensThePageBehindWhatIsShownAndIdleTakesNoClick() {
        #expect(IslandState.recording(since: since).page == .calls)
        #expect(IslandState.reading(names: ["Atlas"], page: .machine(4)).page == .machine(4))
        #expect(IslandState.needsYou(machines: ["Pip"]).page == .day)
        #expect(IslandState.plan(plan).page == .usage)
        #expect(IslandState.idle.page == nil && !IslandState.idle.takesClicks)
    }

    @Test func hoveringSaysOneMoreLine() {
        #expect(IslandState.recording(since: since).detail == "Recording a call")
        #expect(IslandState.reading(names: ["Atlas"], page: .machine(4)).detail == "Atlas is reading")
        #expect(IslandState.reading(names: ["Atlas", "Pip"], page: .crew).detail == "Atlas and Pip are reading")
        #expect(IslandState.needsYou(machines: ["Pip"]).detail == "1 need you, from Pip")
        #expect(
            IslandState.needsYou(machines: ["Relay", "Pip", "Pip", "Relay", "Pip"]).detail
                == "5 need you · Pip 3, Relay 2")
        #expect(IslandState.plan(plan).detail == "Claude plan · 42%")
    }

    @Test func theOtherSideOfAScreenShareSeesTheIslandOnlyWhileACallRecords() {
        #expect(IslandState.recording(since: since).sharingType == .readOnly)
        #expect(IslandState.reading(names: ["Atlas"], page: .crew).sharingType == .none)
        #expect(IslandState.needsYou(machines: ["Pip"]).sharingType == .none)
        #expect(IslandState.plan(plan).sharingType == .none)
        #expect(IslandState.idle.sharingType == .none)
    }
}

@Suite struct IslandMetricsTests {
    private func width(of text: String, digits: Bool = false) -> CGFloat {
        let size = Font.TextStyle.callout.macSize
        let font =
            digits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)
            : NSFont.systemFont(ofSize: size, weight: .medium)
        return NSAttributedString(string: text, attributes: [.font: font]).size().width
    }

    @Test func theEarsHoldTheLongestTimerAndTheCommonLabelsWithoutTruncating() {
        let room = IslandMetrics.earWidth - 2 * IslandMetrics.earInset
        #expect(width(of: "88:88:88", digits: true) <= room)
        #expect(width(of: "9 machines") <= room)
        #expect(width(of: "Quarterly investor update") > room)
    }

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func metrics(left: CGRect?, right: CGRect?, inset: CGFloat) -> IslandMetrics? {
        IslandMetrics(screenWidth: screen.width, leftStrip: left, rightStrip: right, topInset: inset)
    }

    @Test func aScreenWithoutANotchHasNoIsland() {
        #expect(metrics(left: nil, right: nil, inset: 0) == nil)
        #expect(metrics(left: CGRect(x: 0, y: 0, width: 650, height: 32), right: nil, inset: 32) == nil)
        #expect(
            metrics(
                left: CGRect(x: 0, y: 0, width: 650, height: 32), right: CGRect(x: 862, y: 0, width: 650, height: 32),
                inset: 0) == nil)
    }

    @Test func theNotchIsTheGapBetweenTheStripsBesideIt() throws {
        let found = try #require(
            metrics(
                left: CGRect(x: 0, y: 0, width: 650, height: 32), right: CGRect(x: 862, y: 0, width: 650, height: 32),
                inset: 32))
        #expect(found.notch == CGSize(width: 212, height: 32))
    }

    @Test func thePanelHoldsTheOpenShapeAndItsOvershootAtTheTopCentre() {
        let metrics = IslandMetrics.sample
        #expect(
            metrics.panelSize.width == metrics.notchWidth + 2 * IslandMetrics.earWidth + 2 * IslandMetrics.overshoot)
        #expect(metrics.panelSize.height == metrics.notchHeight)
        let frame = metrics.panelFrame(on: screen, isTall: false)
        #expect(frame.midX == screen.midX && frame.maxY == screen.maxY && frame.size == metrics.panelSize)
    }
}

/// The shape and its content take turns: the content shows after the shape has mostly opened, and goes before it
/// closes.
@Suite struct IslandSequenceTests {
    private let recording = IslandState.recording(since: Date(timeIntervalSince1970: 1_790_000_000))
    private let reading = IslandState.reading(names: ["Atlas"], page: .crew)
    private let closed = IslandShown()

    private func open(_ content: IslandState, visible: Bool = true) -> IslandShown {
        IslandShown(content: content, isOpen: true, isContentVisible: visible)
    }

    private func steps(_ shown: IslandShown, _ target: IslandState, reduceMotion: Bool = false) -> [IslandStep] {
        IslandSequence.steps(from: shown, to: target, reduceMotion: reduceMotion)
    }

    @Test func theShapeOpensBeforeItsContentShows() {
        #expect(
            steps(closed, recording) == [
                .setContent(recording), .openShape, .wait(IslandSequence.openLead), .showContent,
            ])
    }

    @Test func aReadingWaitsToSeeIfItLastsButARecordingNeverWaits() {
        #expect(steps(closed, reading).first == .wait(IslandSequence.readingDelay))
        #expect(steps(closed, recording).first == .setContent(recording))
        #expect(steps(open(recording), reading).first == .hideContent)
    }

    @Test func theContentGoesBeforeTheShapeCloses() {
        #expect(
            steps(open(recording), .idle) == [
                .hideContent, .wait(IslandSequence.contentFade), .setContent(.idle), .closeShape,
            ])
    }

    @Test func oneStateReplacesAnotherInsideTheOpenShape() {
        #expect(
            steps(open(recording), reading) == [
                .hideContent, .wait(IslandSequence.contentFade), .setContent(reading), .showContent,
            ])
    }

    @Test func theSameStateAgainMovesNothing() {
        #expect(steps(open(recording), recording).isEmpty)
        #expect(steps(closed, .idle).isEmpty)
    }

    @Test func aChangeOfMindMidwayFinishesFromWhereTheIslandIs() {
        #expect(steps(open(recording, visible: false), recording) == [.showContent])
        #expect(steps(open(recording, visible: false), .idle) == [.setContent(.idle), .closeShape])
        #expect(
            steps(open(recording, visible: false), reading) == [.setContent(reading), .showContent])
    }

    @Test func withReduceMotionNothingWaitsForAShapeToMove() {
        let all = steps(closed, recording, reduceMotion: true) + steps(open(recording), reading, reduceMotion: true)
        #expect(!all.contains { if case .wait(let time) = $0 { time != .zero } else { false } })
        #expect(all.contains(.showContent) && all.contains(.hideContent))
    }

    @Test func theContentFadeIsTheRevealCurve() {
        #expect(Motion.reveal(reduceMotion: false) == .easeOut(duration: 0.18))
        #expect(IslandSequence.contentFade == .milliseconds(180))
    }
}

@MainActor @Suite struct IslandPresenterTests {
    /// Waits up to five seconds, so a busy machine does not fail a test that only needs time.
    private func until(_ condition: () -> Bool) async {
        for _ in 0..<500 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @Test func aScreenChangeUpdatesTheMetricsAndKeepsWhatIsShown() {
        let presenter = IslandPresenter(metrics: .sample, showing: .reading(names: ["Atlas"], page: .crew))
        let wider = IslandMetrics(notch: CGSize(width: 240, height: 40))
        presenter.place(wider)
        #expect(presenter.metrics == wider)
        #expect(
            presenter.content == .reading(names: ["Atlas"], page: .crew) && presenter.isOpen
                && presenter.isContentVisible)
    }

    @Test func theMovesRunInOrderUntilTheIslandShowsTheState() async throws {
        let presenter = IslandPresenter(metrics: .sample)
        presenter.show(.reading(names: ["Atlas"], page: .crew), reduceMotion: true)
        await until { presenter.isContentVisible }
        #expect(presenter.content == .reading(names: ["Atlas"], page: .crew) && presenter.isOpen)
        presenter.show(.idle, reduceMotion: true)
        await until { !presenter.isDrawn }
        #expect(presenter.content == .idle && !presenter.isOpen && !presenter.isContentVisible)
    }

    @Test func aReadingThatEndsBeforeTheDelayNeverOpensTheIsland() async throws {
        let presenter = IslandPresenter(metrics: .sample)
        presenter.show(.reading(names: ["Atlas"], page: .crew), reduceMotion: true)
        try await Task.sleep(for: .milliseconds(100))
        presenter.show(.idle, reduceMotion: true)
        try await Task.sleep(for: IslandSequence.readingDelay + .milliseconds(100))
        #expect(!presenter.isOpen && !presenter.isDrawn && presenter.content == .idle)
    }

    @Test func aNewStateCancelsTheMovesStillRunning() async throws {
        let presenter = IslandPresenter(metrics: .sample)
        presenter.show(.recording(since: .now), reduceMotion: false)
        try await Task.sleep(for: .milliseconds(50))
        presenter.show(.idle, reduceMotion: false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(presenter.content == .idle && !presenter.isOpen && !presenter.isContentVisible)
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

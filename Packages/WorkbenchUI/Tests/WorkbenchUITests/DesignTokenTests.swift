import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

/// A clock that moves only when a test says so, so no test waits for real time.
private final class ManualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private var waiters: [(deadline: Instant, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var now = Instant(offset: .zero)
    let minimumResolution = Duration.zero

    var sleeping: Int { waiters.count }

    /// A cancelled toast timer stays here until its time comes, as a task that ignores cancellation would.
    func untilSleeping(_ count: Int) async {
        await yieldUntil { sleeping >= count }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        await withCheckedContinuation { waiters.append((deadline, $0)) }
    }

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
        let due = waiters.filter { $0.deadline <= now }
        waiters.removeAll { $0.deadline <= now }
        for waiter in due { waiter.continuation.resume() }
    }
}

extension ManualClock.Instant: Comparable {}

/// Lets other tasks run until the condition holds, and gives up after a fixed number of turns so a broken guard fails
/// the test and does not hang it.
private func yieldUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
}

@Suite struct DesignTokenTests {
    @Test func everyMotionTokenStandsStillWithReduceMotionOnAndMovesWithItOff() {
        let tokens: [(String, (Bool) -> Animation?)] = [
            ("settle", Motion.settle), ("snap", Motion.snap), ("reveal", Motion.reveal), ("island", Motion.island),
        ]
        for (name, token) in tokens {
            #expect(token(true) == nil, "\(name) moves under Reduce Motion")
            #expect(token(false) != nil, "\(name) does not move with Reduce Motion off")
        }
    }

    @Test func theTokensCarryTheContractsValues() {
        #expect(Motion.snap(reduceMotion: false) == .spring(response: 0.28, dampingFraction: 0.9))
        #expect(Motion.reveal(reduceMotion: false) == .easeOut(duration: 0.18))
        #expect(Motion.island(reduceMotion: false) == .spring(response: 0.42, dampingFraction: 0.82))
    }

    @Test func sixRolesScaleWithTheZoomAndOnlyMetaAndCaptionAreSupporting() {
        #expect(TextRole.allCases.count == 6)
        #expect(TextRole.allCases.filter(\.isSupporting) == [.meta, .caption])
        for role in TextRole.allCases {
            func width(_ scale: Double) -> CGFloat {
                let text = Text("Review the login API").text(role).environment(\.uiScale, scale).fixedSize()
                return NSHostingView(rootView: text).fittingSize.width
            }
            #expect(width(1.5) > width(1) * 1.3, "\(role) ignores the zoom")
        }
    }

    @Test func aTitleIsLargerThanARowAndARowIsLargerThanItsMeta() {
        func size(_ role: TextRole) -> CGFloat { role.style.macSize }
        #expect(size(.pageTitle) > size(.sectionTitle) && size(.sectionTitle) >= size(.rowTitle))
        #expect(size(.rowTitle) > size(.meta) && size(.meta) > size(.caption))
    }

    @Test func aToastShowsOneAtATimeAndTheNewOneReplacesTheOld() {
        let center = ToastCenter(clock: ManualClock())
        center.show("First", undo: nil)
        center.show("Second", undo: {})
        #expect(center.current?.text == "Second")
        #expect(center.current?.hasUndo == true)
    }

    @Test func aToastGoesAfterFiveSecondsAndNotBefore() async {
        let clock = ManualClock()
        let center = ToastCenter(clock: clock)
        center.show("Marked right", undo: nil)
        await clock.untilSleeping(1)
        clock.advance(by: .milliseconds(4900))
        await Task.yield()
        #expect(center.current != nil)
        clock.advance(by: .milliseconds(100))
        await yieldUntil { center.current == nil }
        #expect(center.current == nil)
    }

    @Test func theOldToastsTimerDoesNotHideTheNewToast() async {
        let clock = ManualClock()
        let center = ToastCenter(clock: clock)
        center.show("First", undo: nil)
        await clock.untilSleeping(1)
        clock.advance(by: .seconds(3))
        center.show("Second", undo: nil)
        await clock.untilSleeping(2)
        clock.advance(by: .seconds(3))
        await Task.yield()
        #expect(center.current?.text == "Second")
        clock.advance(by: .seconds(2))
        await yieldUntil { center.current == nil }
        #expect(center.current == nil)
    }

    @Test func undoRunsTheClosureOnceAndHidesTheToast() {
        let center = ToastCenter(clock: ManualClock())
        var runs = 0
        center.show("Marked right") { runs += 1 }
        center.undo()
        center.undo()
        #expect(runs == 1)
        #expect(center.current == nil)
    }

    @Test func undoAfterTheToastHidAndUndoOfAReplacedToastDoNothing() async {
        let clock = ManualClock()
        let center = ToastCenter(clock: clock)
        var runs: [String] = []
        center.show("First") { runs.append("first") }
        center.show("Second") { runs.append("second") }
        await clock.untilSleeping(2)
        clock.advance(by: .seconds(5))
        await yieldUntil { center.current == nil }
        center.undo()
        #expect(runs.isEmpty)
        center.show("Third") { runs.append("third") }
        center.undo()
        #expect(runs == ["third"])
    }

    @Test func theToastIsDrawnOverTheContentAndNeverMovesIt() {
        let center = ToastCenter(clock: ManualClock())
        let host = NSHostingView(rootView: Color.clear.frame(width: 300, height: 200).toastHost(center))
        let before = host.fittingSize
        center.show("Marked right", undo: {})
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize == before)
        #expect(before == CGSize(width: 300, height: 200))
    }

    private struct Showcase: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Today").text(.pageTitle)
                    Text("Asked of you").text(.sectionTitle)
                    Text("Raj waits on you to pick USD or INR").text(.rowTitle)
                    Text("Raj Patel, WhatsApp, 2 days ago").text(.meta)
                    Text("\"Can you pick USD or INR before Friday?\"").text(.quote)
                    Text("Due Friday").text(.caption)
                }
                HStack(spacing: Space.s) {
                    Chip("Needs you", tone: .attention)
                    Chip("Done", tone: .good)
                    Chip("Wrong", tone: .bad)
                    Chip("Snoozed 3 days", tone: .neutral)
                }
                HStack(spacing: Space.s) {
                    ForEach(["Y", "D", "S", "X", "N", "⌘Z", "Space", "Esc"], id: \.self) { KeyHint($0) }
                }
                ToastView(toast: Toast(id: 1, text: "Marked right", hasUndo: true), undo: {})
                ToastView(toast: Toast(id: 2, text: "Snoozed for 3 days", hasUndo: false), undo: {})
                ToastView(
                    toast: Toast(
                        id: 3,
                        text: "Marked right for Raj Patel and 11 more facts from the WhatsApp group Founders Circle",
                        hasUndo: true), undo: {})
            }
            .padding(Space.l)
            .frame(width: 560, alignment: .leading)
        }
    }

    @Test(arguments: ["light", "dark"], [1.0, 1.5])
    func everyDesignPartIsDrawnInLightAndDarkAtTwoZooms(mode: String, zoom: Double) throws {
        let view = Showcase().zoomed(Zoom(zoom)).background(.pageFill)
            .environment(\.colorScheme, mode == "dark" ? .dark : .light)
        var data: Data?
        NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            data = renderer.nsImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0) }?
                .representation(using: .png, properties: [:])
        }
        let folder = URL(filePath: "/Users/jeet/Projects/worktrace/plans/2026-11-23-ux1/shots/L2")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = try #require(data)
        try png.write(to: folder.appending(path: "design-\(mode)-\(zoom).png"))
        #expect(png.count > 10_000)
    }
}

import Foundation
import Testing

@testable import WorkbenchCore

private let start = WorkDay(containing: t0).start

private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

private func window(_ minutes: Double, _ app: String, _ title: String, _ document: String? = nil) -> Activity {
    Activity(at: at(minutes), kind: .window, app: app, bundleID: "b.\(app)", title: title, document: document)
}

private func marker(_ minutes: Double, _ kind: Activity.Kind) -> Activity { Activity(at: at(minutes), kind: kind) }

private func spans(_ sessions: [ScreenSession]) -> [String] {
    sessions.map {
        "\($0.number) \($0.title) \(Int($0.start.timeIntervalSince(start) / 60))-\(Int($0.end.timeIntervalSince(start) / 60))"
    }
}

@Suite struct SessionTests {
    private let end = start.addingTimeInterval(86_400)

    @Test func aWindowLastsUntilTheNextWindowOrIdleAndBackFromIdleReopensIt() {
        let sessions = Sessions.make(
            from: [
                window(0, "Terminal", "claude"), window(30, "Brave", "Gmail", "https://mail.google.com/mail"),
                marker(40, .idle), marker(50, .active), marker(70, .sleep),
            ], start: start, end: end)
        #expect(spans(sessions) == ["1 claude 0-30", "2 Gmail 30-40", "3 Gmail 50-70"])
    }

    @Test func aGapUpToTwoMinutesOnTheSameWindowJoinsAndALongerOneDoesNot() {
        let short = Sessions.make(
            from: [window(0, "Brave", "Docs"), marker(10, .idle), marker(11.5, .active), window(20, "Terminal", "x")],
            start: start, end: at(30))
        #expect(spans(short) == ["1 Docs 0-20", "2 x 20-30"])
        let long = Sessions.make(
            from: [window(0, "Brave", "Docs"), marker(10, .idle), marker(13, .active), window(20, "Terminal", "x")],
            start: start, end: at(30))
        #expect(spans(long) == ["1 Docs 0-10", "2 Docs 13-20", "3 x 20-30"])
    }

    @Test func aPassThroughUnderTenSecondsIsLeftOutAndTheWindowsAroundItJoin() {
        let sessions = Sessions.make(
            from: [window(0, "Brave", "Docs"), window(5, "Finder", "Desktop"), window(5.1, "Brave", "Docs")],
            start: start, end: at(10))
        #expect(spans(sessions) == ["1 Docs 0-10"])
        let kept = Sessions.make(
            from: [window(0, "Brave", "Docs"), window(5, "Finder", "Desktop"), window(5.2, "Brave", "Docs")],
            start: start, end: at(10))
        #expect(spans(kept).map { String($0.split(separator: " ")[1]) } == ["Docs", "Desktop", "Docs"])
    }

    @Test func aHiddenWindowOrAWakeClosesTheWindowAndActiveDoesNotReopenIt() {
        let sessions = Sessions.make(
            from: [window(0, "Brave", "Docs"), marker(10, .skipped), marker(20, .idle), marker(25, .active)],
            start: start, end: at(30))
        #expect(spans(sessions) == ["1 Docs 0-10"])
        let woken = Sessions.make(
            from: [window(0, "Brave", "Docs"), marker(10, .sleep), marker(20, .wake), marker(21, .active)],
            start: start, end: at(30))
        #expect(spans(woken) == ["1 Docs 0-10"])
    }

    @Test func aWindowOpenedBeforeTheDayIsClippedToItAndTheDayEndClosesTheLast() {
        let sessions = Sessions.make(
            from: [window(-30, "Terminal", "night"), window(15, "Brave", "Docs"), window(2000, "Terminal", "late")],
            start: start, end: at(60))
        #expect(spans(sessions) == ["1 night 0-15", "2 Docs 15-60"])
    }
}

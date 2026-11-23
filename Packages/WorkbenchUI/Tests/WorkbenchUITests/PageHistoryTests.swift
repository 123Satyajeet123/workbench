import Testing

@testable import WorkbenchUI

@Suite struct PageHistoryTests {
    @Test func backAndForwardRetraceThePagesYouOpened() {
        var history = PageHistory()
        #expect(!history.canGoBack && !history.canGoForward)
        history.visit(from: .mochi)
        history.visit(from: .people)
        #expect(history.goBack(from: .usage) == .people)
        #expect(history.goBack(from: .people) == .mochi)
        #expect(history.goBack(from: .mochi) == nil && !history.canGoBack)
        #expect(history.goForward(from: .mochi) == .people)
        #expect(history.goForward(from: .people) == .usage && !history.canGoForward)
    }

    @Test func openingAPageAfterGoingBackDropsTheWayForward() {
        var history = PageHistory()
        history.visit(from: .mochi)
        _ = history.goBack(from: .people)
        history.visit(from: .mochi)
        #expect(!history.canGoForward && history.goBack(from: .timeline) == .mochi)
    }

    @Test func goingBackSkipsAPageThatIsGoneAndHistoryStaysShort() {
        var history = PageHistory()
        history.visit(from: .mochi)
        history.visit(from: .machine(7))
        #expect(history.goBack(from: .people) { $0 != .machine(7) } == .mochi)
        for _ in 0..<200 { history.visit(from: .mochi) }
        #expect(history.back.count == PageHistory.limit)
    }
}

import Testing

@testable import WorkbenchUI

@Suite struct PageHistoryTests {
    @Test func backAndForwardRetraceThePagesYouOpened() {
        var history = PageHistory()
        #expect(!history.canGoBack && !history.canGoForward)
        history.visit(from: .day)
        history.visit(from: .people)
        #expect(history.goBack(from: .usage) == .people)
        #expect(history.goBack(from: .people) == .day)
        #expect(history.goBack(from: .day) == nil && !history.canGoBack)
        #expect(history.goForward(from: .day) == .people)
        #expect(history.goForward(from: .people) == .usage && !history.canGoForward)
    }

    @Test func openingAPageAfterGoingBackDropsTheWayForward() {
        var history = PageHistory()
        history.visit(from: .day)
        _ = history.goBack(from: .people)
        history.visit(from: .day)
        #expect(!history.canGoForward && history.goBack(from: .review) == .day)
    }

    @Test func goingBackSkipsAPageThatIsGoneAndHistoryStaysShort() {
        var history = PageHistory()
        history.visit(from: .day)
        history.visit(from: .machine(7))
        #expect(history.goBack(from: .people) { $0 != .machine(7) } == .day)
        for _ in 0..<200 { history.visit(from: .day) }
        #expect(history.back.count == PageHistory.limit)
    }
}

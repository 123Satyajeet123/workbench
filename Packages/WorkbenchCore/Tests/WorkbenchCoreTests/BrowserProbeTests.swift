import Foundation
import Testing

@testable import WorkbenchCore

/// The offline parts of probes P0, P2 and P3: the verdicts, on made-up data.
@Suite struct BrowserProbeOfflineTests {
    private let opened = Date(timeIntervalSince1970: 1_000)

    @Test func theWorkerIsAliveOnlyWhenEverySampleIsAnsweredOnOneConnection() {
        let steady = (0...5).map { DriverProbe.Sample(minute: $0 * 2, answered: true, connectionOpened: opened) }
        #expect(DriverProbe.workerStayedAlive(steady))
        var missed = steady
        missed[3].answered = false
        #expect(!DriverProbe.workerStayedAlive(missed))
        var restarted = steady
        restarted[4].connectionOpened = opened.addingTimeInterval(400)
        #expect(!DriverProbe.workerStayedAlive(restarted), "a new connection means the worker died and came back")
        var unknown = steady
        unknown[2].connectionOpened = nil
        #expect(!DriverProbe.workerStayedAlive(unknown))
        #expect(!DriverProbe.workerStayedAlive([]))
    }

    @Test func aPageCountsAsLoadedOnlyWhenItsMarkerIsInTheText() {
        let page = DriverProbe.p2Pages[0]
        let whole = FetchedPage(url: page.url, text: "top text. Five  Page\nspread at the bottom")
        let cutOff = FetchedPage(url: page.url, text: "top text only")
        #expect(DriverProbe.result(of: page, .success(whole)).markerFound)
        #expect(!DriverProbe.result(of: page, .success(cutOff)).markerFound)
        #expect(DriverProbe.result(of: page, .failure(.timedOut)).failure != nil)
        #expect(DriverProbe.p2Pages.map(\.name) == ["lazy", "script-drawn", "static"])
    }

    @Test func recallCountsThePagesTheBrowserReadAndTheClaimsItGaveBack() throws {
        let claims = try JSONDecoder().decode(
            [DriverProbe.Claim].self,
            from: Data(
                #"[{"id":"c1","company":"Acme","true_value":"$11 million"},{"id":"c2","company":"Bolt","true_value":"$5 million"},{"id":"c3","company":"Core","true_value":"$2 million"}]"#
                    .utf8))
        let results = try JSONDecoder().decode(
            [DriverProbe.SearchResult].self,
            from: Data(
                #"[{"id":"c1","results":[{"url":"u1"},{"url":"u2"}]},{"id":"c2","results":[{"url":"u3"}]},{"id":"c3","results":[{"url":"u4"}]}]"#
                    .utf8))
        let long = String(repeating: "filler ", count: 100)
        let fetched = ["u1": "short", "u2": "Acme raised $11 Million. " + long, "u3": "", "u4": "blocked"]
        let browsed = [
            "u1": "Acme  RAISED $11 million " + long, "u3": "Bolt raised $5 million " + long, "u4": "still short",
        ]
        let recall = DriverProbe.recall(claims: claims, results: results, fetched: fetched, browsed: browsed)
        #expect(recall.pages == 4 && recall.plainUnreadable == 3)
        #expect(recall.browserReadable == 2, "u4 stays under the threshold")
        #expect(recall.claimsWithValueFromFetch == 1)
        #expect(recall.claimsWithValueAfterBrowser == 2, "Bolt appears only after the browser; Core never does")
    }

    @Test func theValueNeedsTheCompanyNameOnTheSamePage() throws {
        let claim = try JSONDecoder().decode(
            [DriverProbe.Claim].self, from: Data(#"[{"id":"c","company":"Acme","true_value":"$11 million"}]"#.utf8))
        let results = [DriverProbe.SearchResult(id: "c", results: [.init(url: "u")])]
        let long = String(repeating: "x ", count: 300)
        let withoutCompany = DriverProbe.recall(
            claims: claim, results: results, fetched: ["u": "raised $11 million " + long], browsed: [:])
        #expect(withoutCompany.claimsWithValueFromFetch == 0)
    }
}

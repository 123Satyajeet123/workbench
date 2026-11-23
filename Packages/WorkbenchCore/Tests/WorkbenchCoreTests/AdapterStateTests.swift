import Foundation
import Testing

@testable import WorkbenchCore

/// A reader that finds its page changed says so, and the app tells the person in one sentence.
@Suite struct AdapterStateTests {
    private func send(_ json: String, to store: Store) -> PageHost.Reply {
        PageHost.answer(Data(json.utf8), store: store, browser: nil)
    }

    @Test func aStaleReportIsStoredUntilTheSiteReadsAgain() throws {
        let store = try makeStore()
        let stale = send(#"{"type":"adapter_state","site":"Gmail","stale":true}"#, to: store)
        #expect(stale == PageHost.Reply(kept: false))
        #expect(try store.queries.staleAdapters() == ["Gmail"])
        _ = send(#"{"type":"adapter_state","site":"Slack","stale":true}"#, to: store)
        #expect(try store.queries.staleAdapters() == ["Gmail", "Slack"])
        _ = send(#"{"type":"adapter_state","site":"Gmail","stale":false}"#, to: store)
        #expect(try store.queries.staleAdapters() == ["Slack"], "a good read clears the report")
    }

    @Test func aReportThatIsNotASiteNameIsRefusedAndStoresNothing() throws {
        let store = try makeStore()
        for site in ["", "a\\nb", String(repeating: "x", count: 33), "<b>Gmail</b>"] {
            let reply = send(#"{"type":"adapter_state","site":"\#(site)","stale":true}"#, to: store)
            #expect(reply.kept == false && reply.error != nil, "\(site)")
        }
        #expect(try store.queries.staleAdapters().isEmpty)
    }

    @Test func thePersonReadsOneSentenceWithTheSiteName() {
        #expect(AdapterState.sentence(for: "Gmail") == "Workbench cannot read Gmail now: the page changed.")
        #expect(AdapterState.sentence(for: "Slack") == "Workbench cannot read Slack now: the page changed.")
    }
}

import Foundation
import Testing

@testable import GoogleConnector

struct GmailTests {
    private static let labels =
        #"{"labels":[{"id":"INBOX","name":"INBOX"},{"id":"Label_7","name":"Workbench"},{"id":"Label_8","name":"workbench-old"}]}"#
    private static let label = WorkbenchLabel(id: "Label_7")

    @Test func findsTheLabelByExactName() async throws {
        let connector = makeConnector(recorder: Recorder()) { _ in Reply(Self.labels) }
        #expect(try await connector.workbenchLabel(for: "ann@example.com") == .found(Self.label))
    }

    @Test func missingLabelIsATypedResult() async throws {
        let connector = makeConnector(recorder: Recorder()) { _ in
            Reply(#"{"labels":[{"id":"Label_8","name":"workbench"}]}"#)
        }
        #expect(try await connector.workbenchLabel(for: "ann@example.com") == .missing)
    }

    @Test func everyGmailCallThrowsAndSendsNothingWhenMailWasNeverAllowed() async throws {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder, scopes: Set(GoogleEndpoint.calendarScopes)) { _ in
            Reply(Self.labels)
        }
        let email = "ann@example.com"
        let off = GoogleError.gmailNotEnabled(email: email)
        await #expect(throws: off) { try await connector.workbenchLabel(for: email) }
        await #expect(throws: off) { try await connector.messageIDs(in: Self.label, for: email) }
        await #expect(throws: off) { try await connector.message(id: "m1", in: Self.label, for: email) }
        #expect(await recorder.requests.isEmpty)
        #expect(try !connector.gmailEnabled(for: email))
    }

    @Test func calendarCallsNeedOnlyTheCalendarScopes() async throws {
        let connector = makeConnector(recorder: Recorder(), scopes: Set(GoogleEndpoint.calendarScopes)) { _ in
            Reply(#"{"items":[{"id":"a","accessRole":"owner"}]}"#)
        }
        #expect(try await connector.calendars(for: "ann@example.com").map(\.id) == ["a"])
    }

    @Test func mailIsEnabledOnceTheScopeIsGranted() throws {
        let connector = makeConnector(recorder: Recorder()) { _ in Reply("{}") }
        #expect(try connector.gmailEnabled(for: "ann@example.com"))
    }

    @Test func everyListRequestCarriesTheLabelAndNothingBuildsOneWithout() throws {
        let url = try GoogleConnector.messageIDsURL(in: Self.label, pageToken: nil)
        #expect(url.path() == "/gmail/v1/users/me/messages")
        #expect(query(url, "labelIds") == "Label_7")
        #expect(query(url, "q") == nil)
    }

    @Test func listsIdsAcrossPagesUnderTheLabelOnly() async throws {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { request in
            query(request.url, "pageToken") == nil
                ? Reply(#"{"messages":[{"id":"m1"}],"nextPageToken":"p2"}"#) : Reply(#"{"messages":[{"id":"m2"}]}"#)
        }
        #expect(try await connector.messageIDs(in: Self.label, for: "ann@example.com") == ["m1", "m2"])
        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { query($0.url, "labelIds") == "Label_7" })
    }

    @Test func emptyLabelListsNothing() async throws {
        let connector = makeConnector(recorder: Recorder()) { _ in Reply("{}") }
        #expect(try await connector.messageIDs(in: Self.label, for: "ann@example.com").isEmpty)
    }

    @Test func getsAMessageThatCarriesTheLabel() async throws {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { request in
            query(request.url, "format") == "full"
                ? Reply(
                    #"{"id":"m1","labelIds":["Label_7"],"snippet":"Hi","payload":{"mimeType":"text/plain","headers":[{"name":"Subject","value":"Pitch"}],"body":{"size":2,"data":"SGk"}}}"#
                ) : Reply(#"{"id":"m1","labelIds":["Label_7","INBOX"]}"#)
        }
        let message = try await connector.message(id: "m1", in: Self.label, for: "ann@example.com")
        #expect(message.payload?.headers?.first?.value == "Pitch")
        #expect(await recorder.requests.map { query($0.url, "format") } == ["minimal", "full"])
    }

    @Test func refusesAMessageWithoutTheLabelAndNeverFetchesItsContent() async {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { _ in Reply(#"{"id":"m9","labelIds":["INBOX"]}"#) }
        await #expect(throws: GoogleError.messageOutsideWorkbenchLabel(id: "m9")) {
            _ = try await connector.message(id: "m9", in: Self.label, for: "ann@example.com")
        }
        #expect(await recorder.requests.map { query($0.url, "format") } == ["minimal"])
    }

    @Test func refusesAMessageWithNoLabelIdsAtAll() async {
        let connector = makeConnector(recorder: Recorder()) { _ in Reply(#"{"id":"m9"}"#) }
        await #expect(throws: GoogleError.messageOutsideWorkbenchLabel(id: "m9")) {
            _ = try await connector.message(id: "m9", in: Self.label, for: "ann@example.com")
        }
    }

    @Test func refusesAMessageIDThatCouldChangeThePath() async {
        let recorder = Recorder()
        let connector = makeConnector(recorder: recorder) { _ in Reply("{}") }
        await #expect(throws: GoogleError.invalidMessageID("../labels")) {
            _ = try await connector.message(id: "../labels", in: Self.label, for: "ann@example.com")
        }
        #expect(await recorder.requests.isEmpty)
    }
}

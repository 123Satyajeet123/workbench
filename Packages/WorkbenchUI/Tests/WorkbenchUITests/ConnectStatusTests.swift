import Testing

@testable import WorkbenchUI

struct ConnectStatusTests {

    @Test func everyRowIsUndoneUntilTurnedOn() {
        let facts = ConnectFacts(fullDiskAccess: true)
        #expect(facts.status(of: .reader) == .missing)
        for row in ConnectRow.sources { #expect(facts.status(of: row) == .off) }
        #expect(!facts.isSet)
    }

    @Test func aSourceMacOSRefusedPointsToItsPane() {
        let facts = ConnectFacts(
            screenOn: true, calendarOn: true, calendarRefused: true,
            microphoneRefused: true)
        #expect(facts.status(of: .screen) == .needsPermission(pane: "Privacy_Accessibility"))
        #expect(facts.status(of: .whatsApp) == .needsPermission(pane: "Privacy_AllFiles"))
        #expect(facts.status(of: .calendar) == .needsPermission(pane: "Privacy_Calendars"))
        #expect(facts.status(of: .calls) == .needsPermission(pane: "Privacy_Microphone"))
    }

    @Test func allowedSourcesAreReady() {
        let facts = ConnectFacts(
            readerFound: true, screenOn: true, screenTextOn: true, screenTrusted: true, calendarOn: true, callsOn: true,
            mailOn: true, webOn: true)
        for row in ConnectRow.allCases where row != .whatsApp { #expect(facts.status(of: row) == .ready) }
    }

    @Test func whatsAppShowsWhatPipReads() {
        #expect(
            ConnectFacts(fullDiskAccess: true, chats: ["Brave team"]).status(of: .whatsApp) == .chosen("Brave team"))
        #expect(ConnectFacts(fullDiskAccess: true, chats: ["A", "B", "C"]).status(of: .whatsApp) == .chosen("3 chats"))
    }

    @Test func whatsAppAsksForFullDiskAccessBeforeAnyChatIsRead() {
        #expect(ConnectFacts(fullDiskAccess: false).status(of: .whatsApp) == .needsPermission(pane: "Privacy_AllFiles"))
        #expect(
            ConnectFacts(fullDiskAccess: false, chats: ["A"]).status(of: .whatsApp)
                == .needsPermission(pane: "Privacy_AllFiles"))
        #expect(ConnectFacts(fullDiskAccess: true).status(of: .whatsApp) == .off)
    }

    @Test func setNeedsTheReaderAndOneSource() {
        #expect(!ConnectFacts(readerFound: true).isSet)
        #expect(!ConnectFacts(fullDiskAccess: true, chats: ["A"]).isSet)
        #expect(ConnectFacts(readerFound: true, fullDiskAccess: true, chats: ["A"]).isSet)
        #expect(!ConnectFacts(readerFound: true, screenOn: true).isSet)
    }
}

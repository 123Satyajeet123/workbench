import Testing

@testable import WorkbenchUI

struct PaletteTests {
    private let sections = SidebarPlan.sections(
        template: .fund, machines: [SidebarMachine(id: 3, name: "Pip", status: .idle)], today: 0, checks: 0)

    private func commands(capture: CaptureMode = .on, isRecording: Bool = false) -> [PaletteEntry] {
        PaletteEntries.commands(sections: sections, capture: capture, isRecording: isRecording)
    }

    private func facts() -> [PaletteEntry] {
        PaletteEntries.facts([
            (FactFixture.item(1, person: "Meera", quote: "send the signed offer letter"), "Offer letter"),
            (FactFixture.item(2, person: "Raj", quote: "pay the vendor in rupees"), "Vendor payment"),
        ])
    }

    private func titles(_ query: String) -> [String] {
        PaletteSearch.results(for: query, commands: commands(), facts: facts()).map(\.title)
    }

    @Test func noWordsListsEveryPlaceAndActionAndNoFact() {
        let all = titles("")
        #expect(
            all == [
                "Today", "Checks", "People", "Projects", "Calls", "Deals", "Pip", "Team", "Machines", "Mochi",
                "Pause capture for 1 hour", "Turn on private mode", "Record a call…", "Settings",
            ])
    }

    @Test func aPageAMachineAndMochiAreFoundByName() {
        #expect(titles("peo").first == "People")
        #expect(titles("pip") == ["Pip"])
        #expect(titles("mochi") == ["Mochi"])
        #expect(titles("zzzz").isEmpty)
    }

    @Test func aFactIsFoundByWholeWordsOfItsTitleQuoteOrPerson() {
        #expect(titles("offer") == ["Offer letter"])
        #expect(titles("rupees") == ["Vendor payment"])
        #expect(titles("meera") == ["Offer letter"])
        #expect(titles("offer rupees").isEmpty)
        #expect(!titles("o").contains("Offer letter") && !titles("o").contains("Vendor payment"))
    }

    @Test func aFactNeverMatchesInsideAWord() {
        #expect(!titles("ffer").contains("Offer letter"))
        #expect(!titles("signed off").isEmpty)
    }

    @Test func atMostFiveFactsShow() {
        let many = (1...9).map { FactFixture.item(Int64($0), quote: "ship it") }.map { ($0, "Ship \($0.id!)") }
        let found = PaletteSearch.results(for: "ship", commands: [], facts: PaletteEntries.facts(many))
        #expect(found.count == PaletteSearch.factLimit)
    }

    @Test func eachPageShowsItsKeyAndSettingsShowsItsOwn() {
        let all = commands()
        #expect(all.first { $0.title == "Today" }?.shortcut == "⌘1")
        #expect(all.first { $0.title == "Team" }?.shortcut == "⌘7")
        #expect(all.first { $0.title == "Settings" }?.shortcut == "⌘,")
        #expect(all.first { $0.title == "Pip" }?.shortcut == nil)
    }

    @Test func theCaptureActionsFollowTheState() {
        #expect(commands(capture: .paused).map(\.title).contains("Resume capture"))
        #expect(commands(capture: .on).map(\.title).contains("Pause capture for 1 hour"))
        #expect(commands(capture: .privateHour).first { $0.id == "private" }?.action == .privateMode(on: false))
        #expect(commands(capture: .on).first { $0.id == "private" }?.action == .privateMode(on: true))
        #expect(commands(isRecording: true).map(\.title).contains("Stop recording"))
        #expect(!commands(isRecording: true).map(\.title).contains("Record a call…"))
    }

    @Test func aCallIsChosenInTheAppThatPlaysOrInPerson() {
        let choices = PaletteEntries.callChoices(apps: [("us.zoom", "Zoom")])
        #expect(choices.map(\.action) == [.startCall(appID: "us.zoom"), .startCall(appID: nil)])
        #expect(PaletteEntries.callChoices(apps: []).map(\.title) == ["In person (microphone only)"])
    }

    @Test func everyPageWithAKeyHasADistinctKey() {
        let keys = SidebarSelection.fixed.compactMap(\.goKey).map(\.character)
        #expect(keys.count == 7 && Set(keys).count == 7)
    }
}

import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A template that exists in tests only: one news machine, so its only question is about feeds.
private let feedsOnly = TeamTemplate(
    id: "feeds-only", name: "Feeds only", purpose: "Read the news.", objectTypes: [],
    machines: [TeamMachine(template: MachineTemplate.newsSignals.id, name: "News")])

private func onboarding(
    over store: Store, choosing template: TeamTemplate? = nil, templates: [TeamTemplate] = TeamTemplate.builtIn,
    teamStarted: @escaping () -> Void = {}
) -> OnboardingModel {
    let identity = IdentityModel(store: store)
    let team = TeamModel(store: store, me: { identity.identity.name }, templates: templates)
    if let template { team.template = template }
    return OnboardingModel(store: store, identity: identity, team: team, teamStarted: teamStarted)
}

@Suite struct OnboardingTemplateChoiceTests {
    @Test func theChosenTemplateIsSavedWithTheTeamAndRestored() throws {
        let store = try scratchStore()
        let model = onboarding(over: store, choosing: .startupTeam)
        model.advance(to: .connect)
        let reopened = onboarding(over: store)
        #expect(reopened.template == .startupTeam && reopened.screen == .connect)
    }

    @Test func aTemplateThatIsNoLongerOfferedFallsBackToTheFirst() throws {
        let store = try scratchStore()
        onboarding(over: store, choosing: .startupTeam).advance(to: .connect)
        let reopened = onboarding(over: store, templates: [feedsOnly, .blank])
        #expect(reopened.template == feedsOnly)
    }

    @Test func finishingMakesTheMachinesOfTheTemplateOnceInAStoreThatNeverHeldAMachine() throws {
        let store = try scratchStore()
        var started = 0
        let model = onboarding(over: store, choosing: .startupTeam, teamStarted: { started += 1 })
        #expect(model.startsTeam)
        #expect(try store.queries.machines().isEmpty)
        model.advance(to: .done)
        #expect(try store.queries.machines().isEmpty, "nothing is made before the last step")
        model.next()
        #expect(model.isFinished && started == 1)
        #expect(try store.queries.machines().map(\.name) == ["Pip", "Sentinel"])
    }

    @Test func finishingAddsNothingToAStoreThatHeldAMachine() throws {
        let store = try scratchStore()
        try store.seedMachines([(.timeline, "Timeline")])
        let model = onboarding(over: store, choosing: .fund)
        #expect(!model.startsTeam && !model.screens.contains(.setup))
        model.advance(to: .done)
        model.next()
        #expect(model.isFinished)
        #expect(try store.queries.machines().map(\.name) == ["Timeline"])
    }

    @Test func aBlankTeamMakesNoMachine() throws {
        let store = try scratchStore()
        let model = onboarding(over: store, choosing: .blank)
        model.advance(to: .done)
        model.next()
        #expect(model.isFinished)
        #expect(try store.queries.machines().isEmpty)
    }

    @Test func aSavedStepThatNoLongerExistsStartsSetupAgain() throws {
        struct Saved: Codable {
            let index: Int
            let isFinished: Bool
        }
        let store = try scratchStore()
        try StateKey<String>.text("team.template").save(TeamTemplate.blank.id, to: store)
        try StateKey<Saved>.json("onboarding").save(Saved(index: 5, isFinished: false), to: store)
        let reopened = onboarding(over: store)
        #expect(reopened.screen == .welcome && reopened.problem != nil)
    }
}

@Suite struct OnboardingSourcesTests {
    private func rows(of template: TeamTemplate) -> [ConnectRow] { ConnectRow.rows(for: template.sourceNeeds) }

    @Test func connectListsTheReaderAndOnlyTheSourcesTheMachinesNeed() {
        #expect(rows(of: .fund) == [.reader, .mail, .web, .screenText])
        #expect(rows(of: .startupTeam) == [.reader, .whatsApp])
        #expect(rows(of: .blank) == [.reader])
    }

    @Test func aSourceNoMachineNeedsIsNotListedAndOneAMachineNeedsIs() {
        #expect(Set(rows(of: .fund)).isDisjoint(with: [.whatsApp, .screen, .calendar, .calls]))
        var fund = TeamTemplate.fund
        fund.machines.append(TeamMachine(template: MachineTemplate.team.id, name: "Pip"))
        #expect(rows(of: fund).contains(.whatsApp))
    }

    @Test func aSetNeedsOnlyTheRowsOfTheTemplate() {
        let mailOnly = ConnectFacts(readerFound: true, mailOn: true, sourceRows: [.mail])
        #expect(mailOnly.isSet)
        #expect(!ConnectFacts(readerFound: true, sourceRows: [.mail]).isSet)
        #expect(ConnectFacts(readerFound: true, sourceRows: []).isSet, "a team with no source needs only the reader")
        #expect(!ConnectFacts(readerFound: false, sourceRows: []).isSet)
    }

    @Test func aSourceRowIsReadyOnlyWhenItsOwnSwitchIsOn() {
        #expect(ConnectFacts(webOn: true).status(of: .web) == .ready)
        #expect(ConnectFacts().status(of: .web) == .off)
        #expect(
            ConnectFacts(screenTextOn: true).status(of: .screenText) == .needsPermission(pane: .accessibility))
        #expect(ConnectFacts(screenTextOn: true, screenTrusted: true).status(of: .screenText) == .ready)
        #expect(ConnectFacts(mailOn: true).status(of: .mail) == .ready && ConnectFacts().status(of: .mail) == .off)
    }
}

@Suite struct OnboardingSetupStepTests {
    @Test func theSetupStepComesFromTheSpecFieldsOfTheMachines() throws {
        let store = try scratchStore()
        let feeds = onboarding(over: store, choosing: feedsOnly, templates: [feedsOnly, .blank])
        #expect(feeds.questions.map(\.kind) == [.feeds] && feeds.screens.contains(.setup))
        let fund = onboarding(over: try scratchStore(), choosing: .fund)
        #expect(fund.questions.map(\.kind).contains(.criteria) && fund.screens.contains(.setup))
    }

    @Test func equalCriteriaOfTwoMachinesAreAskedOnceAndReachBoth() throws {
        let store = try scratchStore()
        let model = onboarding(over: store, choosing: .fund)
        let criteria = model.questions.filter { $0.kind == .criteria }
        #expect(criteria.count == 1 && criteria[0].machineNames == ["Deal intake", "Outbound"])
        let strict = Criteria(rules: [], hotAt: 7)
        model.answer(criteria[0], with: .criteria(strict))
        model.advance(to: .done)
        model.next()
        let machines = try store.queries.machines()
        #expect(machines.filter { $0.spec.criteria == strict }.map(\.name) == ["Deal intake", "Outbound"])
    }

    @Test func aTemplateWithNoSuchFieldHasNoSetupStep() throws {
        for template in [TeamTemplate.blank, .startupTeam] {
            let model = onboarding(over: try scratchStore(), choosing: template)
            #expect(model.questions.isEmpty && !model.screens.contains(.setup), "\(template.id)")
        }
    }

    @Test func noOnboardingCodeNamesATemplate() throws {
        let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/WorkbenchUI/Onboarding")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count > 5)
        for file in files {
            let hits = TemplateNameSearch.hits(in: try String(contentsOf: file, encoding: .utf8))
            #expect(hits.isEmpty, "\(file.lastPathComponent): \(hits)")
        }
    }

    @Test func theTemplateNameSearchCatchesAPlantedNameAndLeavesPlainCodeAlone() {
        #expect(!TemplateNameSearch.hits(in: #"if template.name == "Fund" { askThesis() }"#).isEmpty)
        #expect(!TemplateNameSearch.hits(in: "let template = TeamTemplate.startupTeam").isEmpty)
        #expect(TemplateNameSearch.hits(in: "let template = model.teamModel.templates[0]").isEmpty)
    }

    @Test func anAnswerBecomesAVersionLikeAnEditOnTheMachinePageAndSkipKeepsTheDefaults() throws {
        let strict = Criteria(rules: [], hotAt: 7)
        let answered = try scratchStore()
        let model = onboarding(over: answered, choosing: .fund)
        let question = try #require(model.questions.first { $0.kind == .criteria })
        model.answer(question, with: .criteria(strict))
        model.advance(to: .done)
        model.next()

        let edited = try scratchStore()
        try edited.startTeam(from: .fund)
        try edited.setCriteria(try #require(edited.queries.machines().first), strict)
        #expect(try answered.queries.machines().first?.spec == (try edited.queries.machines().first?.spec))

        let skipped = try scratchStore()
        let skipping = onboarding(over: skipped, choosing: .fund)
        skipping.advance(to: .done)
        skipping.next()
        #expect(try skipped.queries.machines().first?.spec == MachineTemplate.dealIntake.spec)
    }

    @Test func anAnswerCanBeTakenBack() throws {
        let model = onboarding(over: try scratchStore(), choosing: .fund)
        let question = try #require(model.questions.first)
        model.answer(question, with: .criteria(Criteria()))
        #expect(model.answers.count == 1)
        model.useDefaults(for: question)
        #expect(model.answers.isEmpty)
    }

    @Test func theSummaryNamesMachinesSourcesAndQuestions() throws {
        let model = onboarding(over: try scratchStore(), choosing: .fund)
        model.answer(try #require(model.questions.first), with: .criteria(Criteria()))
        let lines = model.summary(connected: ["Mail"]).lines
        #expect(lines.contains("Machines to make: Deal intake, Outbound, Founder check, and Signals."))
        #expect(lines.contains("Sources on: Mail."))
        #expect(lines.contains("Questions: 1 answered, 2 skipped."))
    }

    @Test func theSummaryOfAKeptStoreAndABlankTeamSaysSo() throws {
        let kept = try scratchStore()
        try kept.seedMachines([(.timeline, "Timeline")])
        #expect(
            onboarding(over: kept, choosing: .fund).summary(connected: []).lines.first
                == "This Mac already has machines. Workbench keeps them and adds none.")
        let blank = onboarding(over: try scratchStore(), choosing: .blank).summary(connected: [])
        #expect(blank.lines == ["No machines yet. You can add them later."])
    }
}

enum TemplateNameSearch {
    static let patterns = [#""Fund""#, #""Startup team""#, #""Blank""#, #"TeamTemplate\.(fund|startupTeam|blank)\b"#]

    static func hits(in text: String) -> [String] {
        patterns.filter { text.range(of: $0, options: .regularExpression) != nil }
    }
}

@Suite struct ListDraftTests {
    private let news = NewsFeed(name: "Inc42", url: URL(string: "https://inc42.com/feed/")!, trusted: true)

    @Test func aFeedListIsReadyOnlyWhenEveryRowHasANameAndAnHttpsAddress() {
        var draft = FeedsDraft([news])
        #expect(draft.feeds == [news] && draft.problem == nil)
        draft.add()
        #expect(draft.feeds == nil && draft.problem != nil)
        draft.rows[1].name = "Mint"
        draft.rows[1].address = "http://mint.example/feed"
        #expect(draft.feeds == nil, "an address with no https is refused")
        draft.rows[1].address = "https://mint.example/feed"
        #expect(draft.feeds?.map(\.name) == ["Inc42", "Mint"] && draft.feeds?[1].trusted == false)
    }

    @Test func aRemovedFeedLeavesTheList() throws {
        var draft = FeedsDraft([news])
        draft.remove(try #require(draft.rows.first))
        #expect(draft.rows.isEmpty && draft.feeds == [])
    }

    @Test func aClaimTypeListNeedsLabelsProofAndDifferentIds() throws {
        let known = ClaimType(id: "funding", label: "funding", proof: "A dated report.")
        var draft = ClaimTypesDraft([known])
        #expect(draft.types == [known])
        draft.add()
        #expect(draft.types == nil, "an empty row blocks the list")
        draft.rows[1].label = "Hiring Plans"
        draft.rows[1].proof = "The careers page."
        #expect(draft.types?.map(\.id) == ["funding", "hiring_plans"], "a new type gets its id from its label")
        draft.rows[1].label = "funding"
        draft.rows[1].proof = "x"
        draft.rows[1].typeID = nil
        #expect(draft.types == nil, "two types with one id are refused")
        draft.remove(draft.rows[1])
        draft.remove(draft.rows[0])
        #expect(draft.types == nil, "a list with no type is refused")
    }
}

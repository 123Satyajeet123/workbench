import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

@Suite struct SetupQuestionTests {
    @Test func aQuestionIsAskedForEachSpecFieldAMachineHas() {
        let fund = TeamTemplate.fund.setupQuestions.map {
            "\($0.machineNames.joined(separator: "+")): \($0.kind.rawValue)"
        }
        #expect(fund == ["Deal intake+Outbound: criteria", "Deal intake: claimTypes", "Signals: feeds"])
    }

    @Test func machinesWithEqualTemplateValuesShareOneQuestionAndUnequalOnesDoNot() {
        func template(_ outbound: Criteria?) -> TeamTemplate {
            TeamTemplate(
                id: "t", name: "T", purpose: "", objectTypes: [],
                machines: [
                    TeamMachine(template: MachineTemplate.dealIntake.id, name: "A"),
                    TeamMachine(
                        template: MachineTemplate.outbound.id, name: "B", overrides: SpecOverrides(criteria: outbound)),
                ])
        }
        #expect(template(nil).setupQuestions.filter { $0.kind == .criteria }.map(\.machines) == [[0, 1]])
        let other = Criteria(rules: [], levels: Level.standard(topCut: 5))
        #expect(template(other).setupQuestions.filter { $0.kind == .criteria }.map(\.machines) == [[0], [1]])
    }

    @Test func aTemplateWithNoSuchFieldAsksNothing() {
        #expect(TeamTemplate.startupTeam.setupQuestions.isEmpty)
        #expect(TeamTemplate.blank.setupQuestions.isEmpty)
    }

    @Test func aTemplateWithOnlyANewsMachineAsksOnlyForFeeds() {
        let news = TeamTemplate(
            id: "news", name: "News", purpose: "", objectTypes: [],
            machines: [TeamMachine(template: MachineTemplate.newsSignals.id, name: "News")])
        #expect(news.setupQuestions.map(\.kind) == [.feeds])
    }

    @Test func aSourceNeedGivesTheReasonOfTheFirstMachineThatReadsIt() throws {
        let needs = TeamTemplate.fund.sourceNeeds
        #expect(needs.map(\.kind) == TeamTemplate.fund.sources)
        let web = try #require(needs.first { $0.kind == .web })
        #expect(web.machine == "Outbound" && web.reason == MachineTemplate.outbound.detail)
    }
}

@Suite struct StartTeamAnswersTests {
    private let strictRules = Criteria(rules: [], levels: Level.standard(topCut: 7))
    private let jobFeed = HiringTemplate.jobFeed

    private func machine(_ name: String, in store: Store) throws -> Machine {
        try #require(store.queries.machines().first { $0.name == name })
    }

    private func versions(of machine: Machine, in store: Store) throws -> Int {
        try store.writer.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM machine_change WHERE machine_id = ?", arguments: [machine.id])
                ?? 0
        }
    }

    @Test func anAnswerIsANewVersionEqualToTheSameEditOnTheMachine() throws {
        let question = try #require(TeamTemplate.fund.setupQuestions.first { $0.kind == .criteria })
        let started = try makeStore()
        let result = try started.startTeam(from: .fund, answers: [question: .criteria(strictRules)])
        let edited = try makeStore()
        try edited.startTeam(from: .fund)
        try edited.setCriteria(try machine("Deal intake", in: edited), strictRules)

        let answered = try machine("Deal intake", in: started)
        #expect(answered.spec == (try machine("Deal intake", in: edited)).spec)
        #expect(answered.spec.criteria == strictRules)
        #expect(try versions(of: answered, in: started) == 2)
        #expect(result.answered == 1 && result.machines.count == 4)
    }

    @Test func noAnswerLeavesTheTemplateValuesAndNoExtraVersion() throws {
        let store = try makeStore()
        try store.startTeam(from: .fund)
        let intake = try machine("Deal intake", in: store)
        #expect(intake.spec == MachineTemplate.dealIntake.spec)
        #expect(try versions(of: intake, in: store) == 1)
    }

    @Test func oneAnswerReachesEveryMachineOfASharedQuestionAsItsOwnVersion() throws {
        let question = try #require(TeamTemplate.fund.setupQuestions.first { $0.kind == .criteria })
        let store = try makeStore()
        let result = try store.startTeam(from: .fund, answers: [question: .criteria(strictRules)])
        #expect(result.answered == 1)
        for name in ["Deal intake", "Outbound"] {
            let machine = try machine(name, in: store)
            #expect(machine.spec.criteria == strictRules)
            #expect(try versions(of: machine, in: store) == 2)
        }
        #expect(try machine("Founder check", in: store).spec.criteria == MachineTemplate.founderCheck.spec.criteria)
    }

    @Test func feedsAndClaimTypesAnswersReachTheirOwnMachines() throws {
        let store = try makeStore()
        let template = HiringTemplate.template
        let answers: SetupAnswers = Dictionary(
            uniqueKeysWithValues: template.setupQuestions.compactMap { question in
                switch question.kind {
                case .feeds: (question, SetupAnswer.feeds([jobFeed]))
                case .claimTypes: (question, SetupAnswer.claimTypes([HiringTemplate.reference]))
                case .criteria: nil
                }
            })
        try store.startTeam(from: template, answers: answers)
        #expect(try machine("Job news", in: store).spec.feeds == [jobFeed])
        #expect(try machine("Applications", in: store).spec.claimTypes == [HiringTemplate.reference])
    }

    @Test func answersAreNotAppliedToAStoreThatHeldAMachine() throws {
        let store = try makeStore()
        try store.seedMachines([(.team, "Pip")])
        let question = try #require(TeamTemplate.fund.setupQuestions.first)
        let result = try store.startTeam(from: .fund, answers: [question: .criteria(strictRules)])
        #expect(result == TeamStart())
        #expect(try store.queries.machines().map(\.name) == ["Pip"])
    }

    @Test func anAnswerForAnotherTemplateIsLeftOut() throws {
        let stale = try #require(HiringTemplate.template.setupQuestions.first { $0.kind == .feeds })
        let store = try makeStore()
        let result = try store.startTeam(from: .startupTeam, answers: [stale: .feeds([jobFeed])])
        #expect(result.answered == 0)
    }

    @Test func aClaimTypeListWithNoTypeANamelessTypeOrARepeatedIdIsRefused() throws {
        let store = try makeStore()
        try store.startTeam(from: .fund)
        let intake = try machine("Deal intake", in: store)
        let good = HiringTemplate.reference
        let nameless = ClaimType(id: "x", label: " ", proof: "p")
        for refused in [[], [nameless], [good, good]] { try store.setClaimTypes(intake, refused) }
        #expect(try machine("Deal intake", in: store).spec.claimTypes == MachineTemplate.dealIntake.spec.claimTypes)
        try store.setClaimTypes(intake, [good])
        #expect(try machine("Deal intake", in: store).spec.claimTypes == [good])
    }

    @Test func aFeedWithNoNameIsRefused() throws {
        let store = try makeStore()
        try store.startTeam(from: .fund)
        let news = try machine("Signals", in: store)
        try store.setFeeds(news, [NewsFeed(name: " ", url: jobFeed.url, trusted: false)])
        #expect(try machine("Signals", in: store).spec.feeds == MachineTemplate.newsSignals.spec.feeds)
        try store.setFeeds(news, [jobFeed])
        #expect(try machine("Signals", in: store).spec.feeds == [jobFeed])
    }

    @Test func aStoreThatHeldAMachineIsKnownEvenWhenTheMachineWasDeleted() throws {
        let store = try makeStore()
        #expect(try !store.queries.holdsMachine())
        try store.seedMachines([(.team, "Pip")])
        try store.setState(try machine("Pip", in: store), .deleted)
        #expect(try store.queries.holdsMachine())
    }
}

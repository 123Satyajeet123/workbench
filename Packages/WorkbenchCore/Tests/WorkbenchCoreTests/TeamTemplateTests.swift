import Foundation
import GRDB
import Testing

@testable import WorkbenchCore

/// A template that exists in tests only. It proves that a new kind of team needs data and no code.
enum HiringTemplate {
    static let candidate = ObjectType(
        id: "hire", noun: "candidate",
        stages: [
            StageDef(id: "hire.applied", label: "Applied", order: 1, meaning: .open),
            StageDef(id: "hire.hired", label: "Hired", order: 2, meaning: .won),
            StageDef(id: "hire.passed", label: "Passed", order: 3, meaning: .lost),
        ])
    static let reference = ClaimType(
        id: "reference", label: "reference", proof: "The referee's own page or a signed letter.")
    static let jobFeed = NewsFeed(name: "Jobs", url: URL(string: "https://jobs.example/feed")!, trusted: false)

    static let template = TeamTemplate(
        id: "hiring", name: "Hiring", purpose: "Follow candidates from application to offer.",
        objectTypes: [candidate],
        machines: [
            TeamMachine(
                template: MachineTemplate.dealIntake.id, name: "Applications",
                overrides: SpecOverrides(brief: "You read applications.", claimTypes: [reference])),
            TeamMachine(
                template: MachineTemplate.newsSignals.id, name: "Job news",
                overrides: SpecOverrides(feeds: [jobFeed])),
        ])
}

/// Finds a built-in team template named in code. Only the built-in template data may name one.
enum TemplateNameScan {
    static let patterns = [#""Fund""#, #""Startup team""#, #""Blank""#, #"TeamTemplate\.(fund|startupTeam|blank)\b"#]

    static func hits(in text: String) -> [String] {
        patterns.filter { text.range(of: $0, options: .regularExpression) != nil }
    }
}

@Suite struct TeamTemplateTests {
    @Test func fundStartupTeamAndHiringAreEachBuiltFromData() {
        #expect(TeamTemplate.fund.seeds.map(\.name) == ["Deal intake", "Outbound", "Founder check", "Signals"])
        #expect(TeamTemplate.fund.objectTypes.map(\.id) == ["deal"])
        #expect(TeamTemplate.startupTeam.seeds.map(\.name) == ["Pip", "Sentinel"])
        #expect(TeamTemplate.startupTeam.objectTypes.map(\.id) == ["project"])
        #expect(
            TeamTemplate.startupTeam.objectTypes.first?.orderedStages.map(\.label) == [
                "Active", "Blocked", "Done", "Dropped",
            ])
        #expect(TeamTemplate.blank.seeds.isEmpty && TeamTemplate.blank.objectTypes.isEmpty)
        #expect(HiringTemplate.template.seeds.map(\.name) == ["Applications", "Job news"])
        #expect(HiringTemplate.template.objectTypes.map(\.id) == ["hire"])
    }

    @Test func everyMachineOfABuiltInTemplateNamesAKnownMachineTemplate() {
        for template in TeamTemplate.builtIn {
            #expect(template.seeds.count == template.machines.count, "\(template.id) names an unknown machine")
        }
    }

    @Test func aTemplateSetsOnlyTheValuesItNames() throws {
        let applications = try #require(HiringTemplate.template.seeds.first)
        #expect(applications.spec.brief == "You read applications.")
        #expect(applications.spec.claimTypes == [HiringTemplate.reference])
        #expect(applications.spec.criteria == HelperSpec.dealIntake.criteria)
        #expect(TeamTemplate.fund.seeds.first?.spec == MachineTemplate.dealIntake.spec)
    }

    @Test func noTemplateNameIsInCodeOutsideTheBuiltInTemplateData() throws {
        var findings: [String] = []
        for file in EgressScan.shippedFiles(repo: NoEgressTests.repo) where file.pathExtension == "swift" {
            guard file.lastPathComponent != "BuiltInTemplates.swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            findings += TemplateNameScan.hits(in: text).map { "\(file.lastPathComponent): \($0)" }
        }
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    @Test func theTemplateNameScanCatchesAPlantedNameAndLeavesPlainCodeAlone() {
        #expect(!TemplateNameScan.hits(in: #"if template.name == "Fund" { addDeals() }"#).isEmpty)
        #expect(!TemplateNameScan.hits(in: "let template = TeamTemplate.startupTeam").isEmpty)
        #expect(TemplateNameScan.hits(in: #"let fund = "Fundamentals"; let blank = template.seeds.isEmpty"#).isEmpty)
    }

    @Test func aTemplateAsksOnlyForTheSourcesItsMachinesRead() {
        #expect(TeamTemplate.fund.sources == [.mail, .web, .screenText])
        #expect(TeamTemplate.startupTeam.sources == [.whatsapp])
        #expect(TeamTemplate.blank.sources.isEmpty)
        #expect(!HiringTemplate.template.sources.contains(.whatsapp))
    }

    @Test func aSourceIsAskedOnceHoweverManyMachinesReadIt() {
        let two = TeamTemplate(
            id: "two", name: "Two", purpose: "", objectTypes: [],
            machines: [
                TeamMachine(template: MachineTemplate.outbound.id, name: "Outbound"),
                TeamMachine(template: MachineTemplate.newsSignals.id, name: "News"),
            ])
        #expect(two.sources == [.web])
    }

    @Test func aTemplateWithNoMailMachineAsksNoMailSourceAndOneWithItDoes() {
        let withoutMail = TeamTemplate(
            id: "x", name: "X", purpose: "", objectTypes: [],
            machines: [TeamMachine(template: MachineTemplate.team.id, name: "Pip")])
        #expect(!withoutMail.sources.contains(.mail))
        var withMail = withoutMail
        withMail.machines.append(TeamMachine(template: MachineTemplate.dealIntake.id, name: "Deals"))
        #expect(withMail.sources.contains(.mail))
    }

    @Test func aMachineTemplateNamesNoFeedOrVendor() {
        for template in MachineTemplate.all {
            #expect(!template.detail.contains("Inc42") && !template.detail.contains("YourStory"))
        }
    }

    @Test func aSpecStoredBeforeFeedsAndClaimTypesExistedStillReadsAndEncodesTheSame() throws {
        let old = try Coding.json(HelperSpec.dealIntake)
        #expect(!old.contains("feeds") && !old.contains("claimTypes"))
        let read = try Coding.value(HelperSpec.self, from: old)
        #expect(read == HelperSpec.dealIntake && read.feeds == nil && read.claimTypes == nil)
    }
}

@Suite struct ExistingStoreUpgradeTests {
    /// A store made before templates were data: its news and deal machines were stored with no list.
    private func oldStore() throws -> Store {
        let store = try makeStore()
        try store.seedMachines(MachineTemplate.seeded.map { ($0.spec, $0.name) })
        try store.createMachine(from: .dealIntake, name: "Deals")
        try store.createMachine(from: .newsSignals, name: "News")
        return store
    }

    @Test func anExistingStoreKeepsItsMachinesAndTheirStoredSpecsAfterTheUpgrade() throws {
        let store = try oldStore()
        let machines = try store.queries.machines()
        #expect(machines.map(\.name) == ["Pip", "Timeline", "Deals", "News"])
        #expect(machines.allSatisfy { $0.state == .active })
        let stored = try store.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM machine_change") }
        #expect(stored == 4, "no machine was written again")
    }

    @Test func aMachineStoredWithNoListsReadsTheListsOfItsTemplate() throws {
        let machines = try oldStore().queries.machines()
        let news = try #require(machines.first { $0.name == "News" })
        let deals = try #require(machines.first { $0.name == "Deals" })
        #expect(news.spec.feeds == MachineTemplate.newsSignals.spec.feeds)
        #expect(deals.spec.claimTypes == MachineTemplate.dealIntake.spec.claimTypes)
        #expect(machines.first { $0.name == "Pip" }?.spec == HelperSpec.team)
    }

    @Test func aListAPersonSetsIsNotReplacedByTheTemplate() throws {
        let store = try makeStore()
        var own = HelperSpec.newsSignals
        own.feeds = [HiringTemplate.jobFeed]
        try store.createMachine(from: own, template: HelperSpec.newsSignals.task, name: "News")
        #expect(try store.queries.machines().first?.spec.feeds == [HiringTemplate.jobFeed])
    }

    @Test func aTeamStartsWithItsTemplateMachinesOnlyInAStoreThatNeverHeldAMachine() throws {
        let fresh = try makeStore()
        try fresh.startTeam(from: .fund)
        #expect(try fresh.queries.machines().map(\.name) == ["Deal intake", "Outbound", "Founder check", "Signals"])
        let old = try oldStore()
        try old.startTeam(from: .fund)
        #expect(try old.queries.machines().map(\.name) == ["Pip", "Timeline", "Deals", "News"])
    }

    @Test func aStoreWhoseMachinesWereAllDeletedIsNotSeededAgain() throws {
        let store = try makeStore()
        try store.seedMachines([(.team, "Pip")])
        try store.setState(try #require(store.queries.machines().first), .deleted)
        try store.startTeam(from: .startupTeam)
        #expect(try store.queries.machines().isEmpty)
    }

    @Test func theClaimTypesAreTheFirstListAMachineHoldsOrNone() throws {
        let store = try makeStore()
        try store.seedMachines([(.team, "Pip")])
        #expect(try store.queries.machines().with(\.checksClaims).first?.spec.claimTypes == nil)
        try store.createMachine(from: .dealIntake, name: "Deals")
        let types = try store.queries.machines().with(\.checksClaims).first?.spec.claimTypes
        #expect(types == MachineTemplate.dealIntake.spec.claimTypes)
    }
}

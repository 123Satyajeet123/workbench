import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct MochiTests {
    private let templates = [
        Mochi.Template(id: "team.ledger", does: "reads one WhatsApp group", views: ["board", "table"]),
        Mochi.Template(id: "day.timeline", does: "turns screen sessions into blocks", views: ["table", "timeline"]),
    ]

    /// One timeline block on each of `count` days, with ids, as the store hands them out.
    private func blocks(days count: Int, in store: Store) async throws -> [Item] {
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        for offset in 0..<count {
            let day = WorkDay(containing: t0).adding(days: -offset)
            let (_, run) = try await model.generate(
                HelperReader.Reply.self, schema: .object([.init("items", .array(.string))]), task: "day.timeline",
                instructions: "v1", input: "x", holding: [])
            let item = Item(
                task: "day.timeline", day: day, scope: "", source: .screen, citeFirst: 1, citeLast: 1,
                start: day.start.addingTimeInterval(3600), end: day.start.addingTimeInterval(7200),
                fields: ["task": "Triage inbound decks", "project": "Fund"], quote: "Deck", run: run)
            try store.saveReading(
                .init(items: [item], dropped: 0, run: run), of: .timeline, day: day, scope: "", grant: grant(.screen))
        }
        return try store.queries.items(of: "day.timeline", since: WorkDay(containing: t0).adding(days: -30))
    }

    private func mochi(_ reply: String, store: Store) -> (Mochi, ScriptedModel) {
        let model = ScriptedModel(reply)
        return (Mochi(model: RecordedModel(model, store: store)), model)
    }

    @Test func fewerThanThreeDaysOfBlocksSendNothing() async throws {
        let store = try makeStore()
        let two = try await blocks(days: 2, in: store)
        let (mochi, model) = mochi(#"{"proposals":[]}"#, store: store)
        let result = try await mochi.propose(blocks: two, roster: [], templates: templates, earlier: [])
        #expect(result == Mochi.Result(proposals: [], dropped: 0, run: nil))
        #expect(model.inputs.withLock { $0.isEmpty })
    }

    @Test func aProposalIsKeptOnlyWithAKnownTemplateAndEvidenceFromThreeOfTheGivenDays() async throws {
        let store = try makeStore()
        let days = try await blocks(days: 4, in: store)
        let ids = days.compactMap(\.id)
        func raw(_ name: String, _ template: String, _ evidence: [Int64]) -> String {
            #"{"name":"\#(name)","template":"\#(template)","brief":"List each deck.","why":"Daily","view":"table","evidence":\#(evidence)}"#
        }
        let raws = [
            raw("Deck triage", "day.timeline", Array(ids.prefix(3))),
            raw("Unknown kind", "crm.sync", Array(ids.prefix(3))),
            raw("Invented block", "day.timeline", [ids[0], ids[1], 999]),
            raw("Two days only", "day.timeline", [ids[0], ids[1]]),
            raw(" ", "day.timeline", Array(ids.prefix(3))),
        ]
        let reply = "{\"proposals\":[" + raws.joined(separator: ",") + "]}"
        let (mochi, _) = mochi(reply, store: store)
        let result = try await mochi.propose(blocks: days, roster: [], templates: templates, earlier: [])
        #expect(result.proposals.map(\.name) == ["Deck triage"])
        #expect(result.dropped == 4)
        #expect(result.proposals.first?.run == result.run)
    }

    @Test func mochiSeesTheBlocksTheRosterTheTemplatesAndEarlierDecisions() async throws {
        let store = try makeStore()
        let days = try await blocks(days: 3, in: store)
        let roster = [Machine(id: 1, name: "Pip", template: "team.ledger", spec: .team, state: .active)]
        let earlier = [
            Proposal(
                run: 1, name: "Deck triage", template: "day.timeline", brief: "b", why: "w", evidence: [],
                decision: .rejected)
        ]
        let (mochi, model) = mochi(#"{"proposals":[]}"#, store: store)
        _ = try await mochi.propose(blocks: days, roster: roster, templates: templates, earlier: earlier)
        let input = try #require(model.inputs.withLock { $0.first })
        #expect(input.contains("- Pip (team.ledger):"))
        #expect(input.contains("- day.timeline: turns screen sessions into blocks Views: table, timeline."))
        #expect(input.contains("- Deck triage (day.timeline): rejected"))
        #expect(input.contains("[\(try #require(days.first?.id))] "))
        #expect(
            input.contains(#"Triage inbound decks — "Deck" — proposed"#)
                || input.contains(#"Fund — Triage inbound decks — "Deck""#))
    }

    @Test func proposalsAreSavedWithScreenConsentAndDecisionsAreHistory() async throws {
        let store = try makeStore()
        let days = try await blocks(days: 3, in: store)
        let ids = days.compactMap(\.id).map(String.init).joined(separator: ",")
        let (mochi, _) = mochi(
            #"{"proposals":[{"name":"Deck triage","template":"day.timeline","brief":"List each deck.","why":"Daily","view":"table","evidence":[\#(ids)]}]}"#,
            store: store)
        let result = try await mochi.propose(blocks: days, roster: [], templates: templates, earlier: [])
        #expect(throws: StoreError.self) { try store.saveProposals(result, grant: grant(.files)) }
        #expect(try store.queries.proposals().isEmpty)
        try store.saveProposals(result, grant: grant(.screen))
        let saved = try #require(store.queries.proposals().first)
        #expect(saved.decision == .waiting && saved.evidence.count == 3)
        try store.decide(try #require(saved.id), .later)
        try store.decide(try #require(saved.id), .accepted)
        #expect(try store.queries.proposals().first?.decision == .accepted)
        #expect(try store.queries.runs().first { $0.task == Mochi.task }?.kept == 1)
    }

    @Test func aProposalKeepsOnlyAViewItsTemplateCanFill() async throws {
        let store = try makeStore()
        let days = try await blocks(days: 3, in: store)
        let ids = days.compactMap(\.id).map(String.init).joined(separator: ",")
        let raws = ["table", "timeline", "board", "chart"].map {
            #"{"name":"Machine \#($0)","template":"day.timeline","brief":"List.","why":"w","view":"\#($0)","evidence":[\#(ids)]}"#
        }
        let (mochi, _) = mochi("{\"proposals\":[" + raws.joined(separator: ",") + "]}", store: store)
        let result = try await mochi.propose(blocks: days, roster: [], templates: templates, earlier: [])
        #expect(result.proposals.map(\.view) == ["table", "timeline"])
        #expect(result.dropped == 2)
    }
}

@Suite struct ViewChoiceTests {
    @Test func eachTemplateOffersTheViewsItsFieldsCanFill() {
        #expect(
            Set(HelperSpec.team.views.keys) == [
                "table", "board", "by kind", "by project", "by stance", "open by project",
            ])
        #expect(Set(HelperSpec.timeline.views.keys) == ["table", "timeline"], "no choice field, no grouped view")
        #expect(HelperSpec.team.views["board"] == .board(groupBy: "person", expected: "members"))
        #expect(Set(HelperSpec.dealIntake.views.keys) == ["table", "by stage", "by rating"])
        #expect(HelperSpec.dealIntake.views["by rating"] == .grouped(by: "rating"))
    }

    @Test func aMachineShowsAnotherViewOnlyIfItsSpecCanFillIt() throws {
        let store = try makeStore()
        let machine = try store.createMachine(from: .timeline, name: "Deck triage")
        try store.show(machine, as: "board")
        #expect(try store.queries.machines().first?.spec.view == .timeline)
        try store.show(machine, as: "table")
        #expect(try store.queries.machines().first?.spec.view == .table)
    }
}

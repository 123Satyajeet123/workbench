import Foundation
import WorkbenchCore

@testable import WorkbenchUI

/// A scratch store filled with a made-up day: facts of three people, a finding of the watch, and the summaries over
/// them. For the tests that render Today. It never touches the founder's store.
enum TodaySample {
    /// A model that gives one fixed reply, so the sample needs no real model.
    private nonisolated struct FixedModel: StructuredModel {
        let name = "sample"
        let reply: String

        func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
            async throws -> ModelAnswer<T>
        {
            ModelAnswer(
                value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "sample", usage: Usage(),
                reply: reply)
        }
    }

    private nonisolated struct NoItems: Decodable, Sendable {}

    static let defaultScope = "sample"

    /// A fact: person, project, kind, text, due day offset from today, and who it asks.
    private struct Fact {
        let person: String
        let project: String
        let kind: String
        let text: String
        let quote: String
        var due: Int?
        var asksFounder = false
    }

    private static let facts = [
        Fact(
            person: "Asha", project: "Login", kind: "commitment", text: "Ship the login API",
            quote: "login API aaj raat tak",
            due: 0),
        Fact(
            person: "Asha", project: "Login", kind: "blocker", text: "Blocked on the signing key",
            quote: "signing key nahi mili", asksFounder: true),
        Fact(
            person: "Raj", project: "Payments", kind: "question", text: "Pay the vendor in USD or INR?",
            quote: "vendor ko USD ya INR?", asksFounder: true),
        Fact(
            person: "Raj", project: "Payments", kind: "done", text: "Finished the payments webhook",
            quote: "webhook done"),
        Fact(
            person: "Meera", project: "Hiring", kind: "plan", text: "Call the designer shortlist",
            quote: "Friday ko designers ko call", due: 3),
        Fact(
            person: "Meera", project: "Hiring", kind: "commitment", text: "Share the offer letter draft",
            quote: "offer letter kal bhejti hoon", due: -1),
        Fact(person: "Asha", project: "Login", kind: "done", text: "Shipped OTA 4.1.11", quote: "OTA 4.1.11 installed"),
    ]

    /// Scope numbers follow the order of names: Asha, Meera, Raj and Hiring, Login, Payments. Facts are 1 to 7.
    nonisolated static let peopleReply = #"""
        {"summaries":[
        {"scope":1,"short":{"text":"Shipped OTA 4.1.11; the login API is due tonight and waits on the signing key.","cites":[1,2,7]},"details":[]},
        {"scope":2,"short":{"text":"The offer letter is a day late; designer calls planned for Friday.","cites":[5,6]},"details":[]},
        {"scope":3,"short":{"text":"Webhook done; asks whether to pay the vendor in USD or INR.","cites":[3,4]},"details":[]}]}
        """#

    nonisolated static let projectsReply = #"""
        {"summaries":[
        {"scope":1,"short":{"text":"Offer letter overdue; designer shortlist calls on Friday.","cites":[5,6]},"details":[]},
        {"scope":2,"short":{"text":"OTA shipped; login API due tonight, blocked on the signing key.","cites":[1,2,7]},"details":[]},
        {"scope":3,"short":{"text":"Webhook done; the vendor currency is undecided.","cites":[3,4]},"details":[]}]}
        """#

    /// Fills the store. Without summaries the day is as a reading that wrote none leaves it.
    static func populate(
        store: Store, crew: Crew, withSummaries: Bool = true, scope: String = defaultScope
    ) async throws {
        let today = WorkDay(containing: store.clock())
        try store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [scope]]))
        guard let pip = crew.machines.first(where: { $0.machine.template == HelperSpec.team.task }) else {
            return
        }
        try await save(facts: facts, of: pip.machine, today: today, scope: scope, store: store)
        if withSummaries {
            try await Summaries(store: store, model: RecordedModel(FixedModel(reply: peopleReply), store: store))
                .refresh(for: today, groupedBy: "person", of: pip.spec.task)
            try await Summaries(store: store, model: RecordedModel(FixedModel(reply: projectsReply), store: store))
                .refresh(for: today, groupedBy: "project", of: pip.spec.task)
        }
        try await saveFinding(crew, today: today, scope: scope, store: store)
    }

    private static func run(_ task: String, in store: Store) async throws -> RunID {
        let model = RecordedModel(FixedModel(reply: "{}"), store: store)
        let (_, run) = try await model.generate(
            NoItems.self, schema: .object([]), task: task, instructions: "sample", input: "sample",
            holding: [.whatsapp])
        return run
    }

    private static func save(facts: [Fact], of machine: Machine, today: WorkDay, scope: String, store: Store)
        async throws
    {
        let run = try await run(machine.task, in: store)
        let items = facts.enumerated().map { index, fact -> Item in
            let at = today.start.addingTimeInterval(Double(index + 1) * 600)
            let due = fact.due.map { today.adding(days: $0).description } ?? ""
            return Item(
                task: machine.task, day: today, scope: scope, source: .whatsapp, citeFirst: Int64(index + 1),
                citeLast: Int64(index + 1), start: at, end: at,
                fields: [
                    "person": fact.person, "project": fact.project, "kind": fact.kind, "text": fact.text, "eta": due,
                    "stance": "said", "asks": fact.asksFounder ? "founder" : "team",
                ], quote: fact.quote, run: run)
        }
        try store.saveReading(
            HelperReader.Result(items: items, dropped: 0, run: run), of: machine.spec, day: today, scope: scope,
            grant: try await store.grant(for: .whatsapp, label: scope, at: store.clock()), replacing: false)
    }

    private static func saveFinding(_ crew: Crew, today: WorkDay, scope: String, store: Store) async throws {
        guard let id = crew.create(from: .derailment, name: "Sentinel"), let sentinel = crew.helper(id: id) else {
            return
        }
        let run = try await run(sentinel.spec.task, in: store)
        let finding = Item(
            task: sentinel.spec.task, day: today, scope: scope, source: .whatsapp, citeFirst: 6, citeLast: 6,
            start: today.start, end: today.start,
            fields: [
                "kind": "overdue", "project": "Hiring", "severity": "act", "next": "Ask Meera for the offer letter",
                "reason": "She promised it for yesterday and nobody mentioned it since.", "facts": "6",
            ], quote: "offer letter kal bhejti hoon", run: run)
        try store.saveReading(
            HelperReader.Result(items: [finding], dropped: 0, run: run), of: sentinel.spec, day: today, scope: scope,
            grant: try await store.grant(for: .whatsapp, label: scope, at: store.clock()), replacing: false)
    }
}

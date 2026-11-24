import EditorHarness
import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

/// A model that answers every call with one fixed reply, as a model that decided in a known way.
final class Scripted: StructuredModel, Sendable {
    let name = "scripted"
    let reply: String

    init(_ reply: String) { self.reply = reply }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "s", usage: Usage(), reply: reply)
    }
}

/// A scripted reading of invented lines through the real reader and the real Verifier: three facts that quote their
/// line, and one whose quote is not in the line it cites.
@MainActor
enum Reading {
    static let lines = [
        "Asha: Example Cafe wants the menu by Friday", "Ravi: the login page for Sample Studio is done",
        "Asha: Sample Studio asked for a call about the invoice", "Ravi: the new menu is printed",
    ]

    /// What the scripted model says: one item for each of the first three lines, and a fourth that quotes words the
    /// line does not hold.
    static func reply(for spec: HelperSpec) -> String {
        let items = [
            (1, "Example Cafe wants the menu", "Example Cafe wants the menu by Friday"),
            (2, "The login page for Sample Studio is done", "the login page for Sample Studio is done"),
            (3, "Sample Studio asked for a call", "Sample Studio asked for a call"),
            (4, "The menu is printed", "words that no line holds"),
        ]
        let cites = items.map { number, text, quote in
            let cite =
                spec.citation == .range ? #""first":\#(number),"last":\#(number)"# : #""cite":\#(number)"#
            return #"{"text":"\#(text)",\#(cite),"quote":"\#(quote)"}"#
        }
        return #"{"items":[\#(cites.joined(separator: ","))]}"#
    }

    static func evidence(at moment: Date) -> EvidenceSet {
        EvidenceSet(
            lines: lines.enumerated().map {
                Evidence(id: Int64($0.offset + 1), start: moment, line: $0.element, quotable: [$0.element])
            })
    }

    /// Reads today's lines for `helper` with the scripted model and saves the reading. Returns the result.
    static func read(_ helper: HelperModel, in scratch: Scratch) async throws -> HelperReader.Result {
        let spec = helper.spec
        let kind = spec.source.consent
        let scope = "invented-\(kind.rawValue)"
        let policy = CapturePolicy(switches: [kind: true], allowList: [kind: [scope]])
        guard let grant = policy.authorize(CaptureRequest(kind: kind, label: scope), at: Date()).grant else {
            throw DemoFailure("no grant for \(kind.rawValue)")
        }
        let reader = HelperReader(spec: spec, model: RecordedModel(Scripted(reply(for: spec)), store: scratch.store))
        let day = WorkDay(containing: Date())
        var result: HelperReader.Result?
        _ = try await reader.readDay(day: day, scope: scope, evidence: evidence(at: Date())) { part in
            try scratch.store.saveReading(part, of: spec, day: day, scope: scope, grant: grant)
            result = part
        }
        guard let result else { throw DemoFailure("no reading") }
        return result
    }

    static func run(_ machines: [HelperModel], in scratch: Scratch) async throws {
        heading("4. A scripted reading of invented lines, through the real Verifier")
        for helper in machines {
            let result = try await read(helper, in: scratch)
            let kept = try scratch.store.queries.items(of: helper.spec.task, on: WorkDay(containing: Date()))
            let texts = kept.map { $0[helper.spec.title] }.sorted()
            print(
                "  \(helper.spec.source.name): kept \(result.items.count), dropped \(result.dropped) \(result.droppedByRule)"
            )
            check(
                "\(helper.spec.source.name): three cited facts kept, the fact with a quote not in its line dropped",
                result.items.count == 3 && result.dropped == 1 && result.droppedByRule[.quoteNotInLines] == 1
                    && kept.count == 3 && !texts.contains("The menu is printed"))
            check(
                "\(helper.spec.source.name): each kept fact quotes words that its own line holds",
                kept.allSatisfy { fact in lines.contains { $0.contains(fact.quote) } })
        }
        scratch.crew.reload()
    }
}

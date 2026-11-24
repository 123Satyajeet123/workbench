import Foundation

/// One synthetic fact of an eval fixture: the fields of the machine's spec that it fills, and the stored line it quotes.
struct PageEvalFact: Sendable {
    let id: Int
    let day: String
    let fields: [String: String]
    let quote: String
    let line: String
    let at: Int64
    let chat: String

    var time: Date { Date(timeIntervalSince1970: Double(at) / 1000) }

    /// The fields of the team machine's spec that a fact of the team fixture fills. `stance` is said when the fact is
    /// about the person who wrote the line. The fixture has no signal for `asks` or `when`, so every fact is `team` and
    /// none has a due.
    static func teamFields(
        person: String, project: String, kind: String, text: String, saidBy: String
    ) -> [String: String] {
        [
            "person": person, "project": project, "kind": kind, "text": text,
            "stance": saidBy == person ? "said" : "reported", "asks": "team",
        ]
    }

    /// The 33 facts of the demo days, as `PageEvalFacts.json` holds them.
    static func load() throws -> [PageEvalFact] {
        guard let url = Bundle.module.url(forResource: "PageEvalFacts", withExtension: "json") else {
            throw PageEvalError.missingFacts
        }
        return try JSONDecoder().decode([TeamRow].self, from: Data(contentsOf: url)).map(\.fact)
    }

    private struct TeamRow: Decodable {
        let id: Int
        let day: String
        let person: String
        let kind: String
        let project: String
        let text: String
        let quote: String
        let line: String
        let at: Int64
        let chat: String
        let saidBy: String

        private enum CodingKeys: String, CodingKey {
            case id, day, person, kind, project, text, quote, line, at, chat
            case saidBy = "said_by"
        }

        var fact: PageEvalFact {
            PageEvalFact(
                id: id, day: day,
                fields: teamFields(person: person, project: project, kind: kind, text: text, saidBy: saidBy),
                quote: quote, line: line, at: at, chat: chat)
        }
    }
}

enum PageEvalError: Error, CustomStringConvertible {
    case missingFacts
    case fixture(String)
    case costLimit(model: String, run: Int, usd: Double)

    var description: String {
        switch self {
        case .missingFacts: "PageEvalFacts.json is not in the Evals bundle"
        case .fixture(let why): "the fixture failed: \(why)"
        case .costLimit(let model, let run, let usd):
            String(format: "stopped: run %d of %@ cost %.2f USD, over the limit", run, model, usd)
        }
    }
}

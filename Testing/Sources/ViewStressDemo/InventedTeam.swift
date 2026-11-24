import Foundation

@testable import WorkbenchCore

/// Nine invented people, six invented projects and five work days: the shape of a team chat, with long names, long
/// quotes, words in several scripts, some facts late, some closed, one person with fifteen facts and two with one.
enum InventedTeam {
    static let people: [(name: String, count: Int)] = [
        ("Anantharaman Venkataraghavan Example", 15), ("Benedikt Varga Example", 10), ("Dominika Kowalczyk Example", 9),
        ("Emeka Example", 7), ("Farida Example", 6), ("Giovanni Rossi Example", 5), ("Hyun-woo Park Example", 4),
        ("Ines Example", 1), ("Jomo Example", 1),
    ]
    static let projects = [
        "Harbor release", "Lantern onboarding", "Billing rewrite", "Field tablets", "Partner portal", "General",
    ]
    private static let things = [
        "build pipeline", "signing key request", "pricing page", "invoice export", "tablet update",
        "onboarding checklist", "partner contract draft", "test report", "release notes", "demo script", "refund flow",
        "data backup",
    ]
    private static let whens = ["by Friday", "on Monday", "before noon tomorrow", "by the end of the week"]
    private static let frames: [String: [String]] = [
        "plan": [
            "I will finish the %@ before the review.", "Next I start the %@ and share it with the team.",
            "Planning to test the %@ on two devices this week.",
        ],
        "done": [
            "The %@ is finished and uploaded.", "I sent the %@ to everyone this morning.",
            "Closed the last open item on the %@.",
        ],
        "blocker": [
            "I am stuck on the %@: the access I asked for has not come.",
            "The %@ cannot move until the budget is approved.", "Waiting for a reply about the %@ for three days now.",
        ],
        "commitment": ["I promise the %@ %@.", "You will have the %@ %@, I give my word."],
        "decision": [
            "We decided to drop the old %@ and keep the new one.", "Agreed: the %@ goes first, then the rest.",
        ],
        "question": [
            "Can you approve the %@ today? The partner is waiting.", "Should the %@ include the second region?",
        ],
        "status": ["The %@ is at 70 percent, two items remain."],
    ]
    private static let kinds = [
        "plan", "done", "plan", "blocker", "commitment", "done", "question", "status", "decision", "plan", "done",
        "commitment", "blocker", "plan", "done",
    ]
    private static let otherScripts = [
        "कल तक %@ भेज दूँगा, अभी जाँच चल रही है।", "来週までに%@を終わらせます。", "Kal tak %@ bhej dunga, abhi testing chal rahi hai.",
        "سأرسل %@ قبل نهاية الأسبوع.",
    ]
    private static let longTail =
        " The reason is simple: the second review found three gaps, the partner changed the dates twice, and the test devices were busy until late on Thursday, so every step after this one moves by a day unless somebody frees a device this week."

    static func facts() -> [InventedFact] {
        var made: [InventedFact] = []
        for (person, entry) in people.enumerated() {
            for index in 0..<entry.count {
                let kind = kinds[(index + person) % kinds.count]
                let thing = things[(person * 5 + index * 7) % things.count]
                let number = made.count
                var words = sentence(
                    kind: kind, thing: thing, variant: index + person, when: whens[number % whens.count])
                if number % 11 == 4 { words = String(format: otherScripts[number % otherScripts.count], thing) }
                if number % 17 == 6 { words += longTail }
                if made.contains(where: { $0.quote == words }) { words += " (\(entry.name.prefix(3)) \(number))" }
                let opens = ["plan", "blocker", "commitment", "question", "decision"].contains(kind)
                made.append(
                    InventedFact(
                        quote: words,
                        fields: [
                            "person": entry.name, "project": projects[(person + index / 3) % projects.count],
                            "kind": kind, "text": words, "when": kind == "commitment" ? whens[number % 4] : "",
                            "stance": number % 9 == 0 ? "reported" : "said",
                            "asks": kind == "question" || (kind == "blocker" && number % 2 == 0) ? "founder" : "team",
                        ],
                        daysAgo: number % 5,
                        dueInDays: opens && kind != "question" ? [-3, -1, 0, 2, 4, nil, 1][number % 7] : nil,
                        closedAs: opens && number % 6 == 5 ? (kind == "blocker" ? "resolved" : "kept") : nil))
            }
        }
        return made
    }

    private static func sentence(kind: String, thing: String, variant: Int, when: String) -> String {
        let options = frames[kind] ?? []
        let frame = options[variant % options.count]
        return frame.contains("%@ %@") ? String(format: frame, thing, when) : String(format: frame, thing)
    }

    /// One cited line per person and per project, as a model would write it: what is done, what is stuck, what is next.
    static func summaries(of items: [Item], run: RunID) -> [String: Summary] {
        var made: [String: Summary] = [:]
        for field in ["person", "project"] {
            for (value, group) in Dictionary(grouping: items, by: { $0[field] }) {
                let pick = { (kind: String) in group.first { $0["kind"] == kind } }
                let parts = [
                    pick("done").map { "finished the \(thing(in: $0))" },
                    pick("blocker").map { "is stuck on the \(thing(in: $0))" },
                    pick("plan").map { "plans the \(thing(in: $0)) next" },
                ].compactMap { $0 }
                guard !parts.isEmpty else { continue }
                let cited = [pick("done"), pick("blocker"), pick("plan")].compactMap { $0?.id }
                made["\(field): \(value)"] = Summary(
                    scope: "\(field): \(value)",
                    short: Summary.Line(text: parts.joined(separator: ", ").capitalizedFirst + ".", cites: cited),
                    details: [], run: run)
            }
        }
        return made
    }

    private static func thing(in item: Item) -> String { things.first { item.quote.contains($0) } ?? "work" }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

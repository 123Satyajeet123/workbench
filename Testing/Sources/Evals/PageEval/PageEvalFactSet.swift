import Foundation

@testable import WorkbenchCore

/// The facts and the machine a task runs on. Every fact is made by code, the same on every call.
enum PageEvalFactSet: String, Codable, Sendable {
    /// The 33 demo facts of the team machine.
    case demo
    /// About 300 facts of the team machine: the 33, and more of the same people, projects and kinds with new ones.
    case large
    /// About 30 deals of a deal-intake machine.
    case fund

    var spec: HelperSpec { self == .fund ? .dealIntake : .team }
    var folderName: String { self == .fund ? "Deals (synthetic)" : "Team (synthetic)" }
    var machineName: String { self == .fund ? "Deal intake" : "Pip" }
    var seededTitle: String { self == .fund ? "All deals" : "All facts" }
    var seededColumns: [String] {
        self == .fund ? ["company", "sector", "stage", "from", "rating"] : ["person", "kind", "project", "text"]
    }

    /// The paragraphs of the person that a fund page has, in place of the team page's.
    var paragraphs: [String]? {
        self == .fund
            ? [
                "Job: read my deal mail and rate each startup.",
                "Partner meeting: every Monday at 10.",
            ] : nil
    }

    func facts(demo: [PageEvalFact]) -> [PageEvalFact] {
        switch self {
        case .demo: demo
        case .large: demo + PageEvalFactSet.largeExtras(after: demo)
        case .fund: PageEvalFactSet.deals()
        }
    }

    // MARK: the larger team set

    static let largeExtraCount = 267
    private static let extraPeople = ["Meera Nair", "Kabir Shah", "Isha Menon"]
    private static let extraProjects = ["Harbor Pilot", "Orchid Billing", "Mintwave Rollout"]
    private static let extraDays = [
        "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-16", "2026-11-17", "2026-11-18",
        "2026-11-19",
    ]
    private static let kindWords: [String: String] = [
        "plan": "Plans to close", "done": "Finished", "blocker": "Is stuck on", "commitment": "Promised to deliver",
        "decision": "Decided to ship", "question": "Asked who owns", "status": "Reports progress on",
    ]

    /// More facts of the same people, projects and kinds as `demo`, with new people and projects. The kinds, people
    /// and projects take turns by the index of the fact, so the set is the same on every call. Each text is unique and
    /// is its own quote inside its own line.
    private static func largeExtras(after demo: [PageEvalFact]) -> [PageEvalFact] {
        let people = distinct("person", in: demo) + extraPeople
        let projects = distinct("project", in: demo) + extraProjects
        let kinds = kindWords.keys.sorted()
        let firstID = (demo.map(\.id).max() ?? 0) + 1
        return (0..<largeExtraCount).map { index in
            let person = people[index % people.count]
            let project = projects[(index * 7 + index / people.count) % projects.count]
            let kind = kinds[(index * 3 + index / 7) % kinds.count]
            let writer = index % 3 == 0 ? people[(index + 1) % people.count] : person
            let text = "\(person) \((kindWords[kind] ?? "").lowercased()) step \(index + 1) of \(project)."
            let day = extraDays[index % extraDays.count]
            return PageEvalFact(
                id: firstID + index, day: day,
                fields: PageEvalFact.teamFields(
                    person: person, project: project, kind: kind, text: text, saidBy: writer),
                quote: text, line: "\(project) update \(index + 1): \(text) Details are in the thread.",
                at: milliseconds(day: day, minute: index), chat: demo.first?.chat ?? "")
        }
    }

    private static func distinct(_ field: String, in facts: [PageEvalFact]) -> [String] {
        facts.reduce(into: [String]()) { names, fact in
            if let name = fact.fields[field], !names.contains(name) { names.append(name) }
        }
    }

    // MARK: the fund

    private static let companies = [
        "Kestrel Ledger", "Orchid Billing", "Harbor Pilot", "Mintwave", "Tessel Health", "Granth Labs", "Paperkite",
        "Lumen Grid", "Okra Freight", "Vellum AI", "Sparrow Pay", "Cobalt Farms", "Nimbus Rx", "Alder Robotics",
        "Quill Learn", "Saffron Cloud", "Bramble Bikes", "Tidepool Data", "Juniper Legal", "Zephyr Cold",
        "Marlin Insure", "Pinecone Rent", "Fable Games", "Ironleaf Steel", "Dune Solar", "Cedar Wallet", "Lotus Care",
        "Rivet Build", "Aurora Mapper", "Banyan Pay",
    ]
    private static let sectors = [
        "fintech", "health", "logistics", "climate", "edtech", "legal", "ai tooling", "retail",
    ]
    private static let stages = ["pre-seed", "seed", "seed", "series A", "later", "unknown"]
    private static let introducers = ["Asha Rao", "Dev Malhotra", "Nina Joshi", "Sam Pereira", "Tara Bose"]
    private static let dealDays = [
        "2026-11-16", "2026-11-17", "2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23",
    ]
    static let dealScope = "deals@synthetic.invalid"

    /// One deal for each company. Every fifth deal is hot; the next two are warm; the others are cold.
    private static func deals() -> [PageEvalFact] {
        companies.enumerated().map { index, company in
            let sector = sectors[index % sectors.count]
            let stage = stages[index % stages.count]
            let rating = index % 5 == 0 ? "hot" : (index % 5 < 3 ? "warm" : "cold")
            let day = dealDays[index % dealDays.count]
            let quote = "\(company) builds \(sector) software."
            return PageEvalFact(
                id: index + 1, day: day,
                fields: [
                    "company": company, "sector": sector, "stage": stage,
                    "from": introducers[index % introducers.count], "rating": rating,
                ], quote: quote,
                line: "Intro: \(company) is raising a \(stage) round. \(quote) Deck attached.",
                at: milliseconds(day: day, minute: index), chat: dealScope)
        }
    }

    private static func milliseconds(day: String, minute: Int) -> Int64 {
        let start = ISO8601DateFormatter().date(from: "\(day)T09:00:00Z") ?? Date(timeIntervalSince1970: 0)
        return Int64((start.timeIntervalSince1970 + Double(minute) * 60) * 1000)
    }
}

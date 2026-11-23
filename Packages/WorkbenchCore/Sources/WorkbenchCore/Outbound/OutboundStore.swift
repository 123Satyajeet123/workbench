import Foundation

/// A startup the investor turned down with "Not a fit", and why when they said. The reasons are kept as data for the
/// investor's later edits of the criteria; nothing applies them by itself.
public struct Rejection: Codable, Sendable, Equatable {
    public var company: String
    public var domain: String?
    public var reason: String
    public var at: Date
}

/// What one run did, kept so the investor sees which queries were sent and what the run cost.
public struct OutboundRunRecord: Codable, Sendable, Equatable {
    public var at: Date
    public var queries: [RuleQuery]
    public var pagesRead: Int
    public var found: Int
    public var kept: Int
    public var alreadyKnown: Int
    /// The monthly cap stopped the searches before every query was sent.
    public var stoppedByCap: Bool
    public var cost: OutboundCost
}

extension Store {
    static func rejectionsKey(_ task: String) -> String { "\(task).outbound.rejections" }
    static func outboundRunsKey(_ task: String) -> String { "\(task).outbound.runs" }
    static let outboundRunsKept = 20

    /// "Not a fit": the startup is remembered with the reason, then the item is marked wrong and hidden. A later run
    /// leaves it out by name or domain.
    public func rejectCandidate(_ item: Item, reason: String) throws {
        guard let id = item.id else { return }
        let entry = Rejection(
            company: item["company"], domain: item["domain"].cleaned, reason: reason.cleaned ?? "", at: clock())
        try saveState(
            try Coding.json(try queries.rejections(task: item.task) + [entry]), forKey: Self.rejectionsKey(item.task))
        try apply(.wrong, to: [id], surface: .review)
    }

    /// "Add to Deals", after the deal exists: the candidate is marked right, and its domain is kept with the deal so a
    /// later run knows the company by domain as well as by name.
    public func acceptCandidate(_ item: Item, asDeal deal: String) throws {
        guard let id = item.id else { return }
        if let domain = item["domain"].cleaned {
            let entry = WatchEntry(name: item["company"], domain: domain, deal: deal)
            try saveWatchEntries(try queries.watchEntries() + [entry])
        }
        try mark(item: id, as: .confirmed)
    }

    /// "Snooze": the candidate leaves the list until `day` and comes back with no new reading.
    public func snoozeCandidate(_ item: Item, until day: WorkDay) throws {
        guard let id = item.id else { return }
        try apply(.snooze(until: day), to: [id], surface: .review)
    }

    func recordOutboundRun(_ record: OutboundRunRecord, task: String) throws {
        let kept = Array((try queries.outboundRuns(task: task) + [record]).suffix(Self.outboundRunsKept))
        try saveState(try Coding.json(kept), forKey: Self.outboundRunsKey(task))
    }
}

extension Queries {
    public func rejections(task: String) throws -> [Rejection] {
        try state(forKey: Store.rejectionsKey(task)).flatMap { try? Coding.value([Rejection].self, from: $0) } ?? []
    }

    /// The runs of a machine, oldest first.
    public func outboundRuns(task: String) throws -> [OutboundRunRecord] {
        try state(forKey: Store.outboundRunsKey(task)).flatMap { try? Coding.value([OutboundRunRecord].self, from: $0) }
            ?? []
    }

    /// Who the investor already knows, for a machine: deals, followed companies and its own rejections.
    public func knownCompanies(task: String) throws -> KnownCompanies {
        KnownCompanies(
            deals: WorkObject.fold(try workEvents(), viewer: ""), entries: try watchEntries(),
            rejections: try rejections(task: task))
    }
}

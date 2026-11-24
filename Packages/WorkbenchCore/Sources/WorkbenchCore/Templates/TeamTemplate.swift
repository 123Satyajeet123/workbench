import Foundation

/// The values a team template sets in a machine's spec, over the machine template's own. A nil value keeps the
/// machine template's.
public struct SpecOverrides: Codable, Sendable, Equatable {
    public var brief: String?
    public var criteria: Criteria?
    public var feeds: [NewsFeed]?
    public var claimTypes: [ClaimType]?

    public init(
        brief: String? = nil, criteria: Criteria? = nil, feeds: [NewsFeed]? = nil, claimTypes: [ClaimType]? = nil
    ) {
        self.brief = brief
        self.criteria = criteria
        self.feeds = feeds
        self.claimTypes = claimTypes
    }

    func applied(to spec: HelperSpec) -> HelperSpec {
        var spec = spec
        spec.brief = brief ?? spec.brief
        spec.criteria = criteria ?? spec.criteria
        spec.feeds = feeds ?? spec.feeds
        spec.claimTypes = claimTypes ?? spec.claimTypes
        return spec
    }
}

/// One item of a team template: the gallery template's id, the name of the machine it makes, and what the team
/// changes in that machine. An item with no machine sets up only its folder.
public struct TeamMachine: Sendable, Equatable {
    public let template: String
    public var name: String
    public var overrides: SpecOverrides

    public init(template: String, name: String, overrides: SpecOverrides = SpecOverrides()) {
        self.template = template
        self.name = name
        self.overrides = overrides
    }
}

/// How a team starts, as data: the kinds of work object it tracks and the gallery items it sets up. A new kind of
/// team is a new value of this type, never new code.
public struct TeamTemplate: Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    /// One line on what a team made from this template is for.
    public var purpose: String
    public var objectTypes: [ObjectType]
    public var machines: [TeamMachine]
    /// Machines a team of this template may add: it starts without them unless the person asks (`adding(optional:)`).
    public var optionalMachines: [TeamMachine]

    public init(
        id: String, name: String, purpose: String, objectTypes: [ObjectType], machines: [TeamMachine],
        optionalMachines: [TeamMachine] = []
    ) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.objectTypes = objectTypes
        self.machines = machines
        self.optionalMachines = optionalMachines
    }

    /// This template with the optional machines the person asked for, by machine template id, after its own.
    public func adding(optional chosen: Set<String>) -> TeamTemplate {
        var template = self
        template.machines += optionalMachines.filter { chosen.contains($0.template) }
        return template
    }

    /// Whether a machine of this template follows companies in the news.
    public var watchesCompanies: Bool { seeds.contains { $0.spec.source.followsCompanies } }

    /// The gallery items it sets up, in order. An item whose template is unknown is left out.
    public var items: [GalleryTemplate] { entries.map(\.item) }

    /// The machines to make, each with its spec set.
    public var seeds: [(spec: HelperSpec, name: String)] {
        entries.compactMap { entry in
            entry.item.machine.map { (entry.machine.overrides.applied(to: $0.spec), entry.machine.name) }
        }
    }

    /// The kinds of source the machines read, each once, in the order the machines first need them.
    public var sources: [SourceKind] { sourceNeeds.map(\.kind) }

    /// Each kind of source the machines read, with the first machine that needs it and the reason that machine gives.
    public var sourceNeeds: [SourceNeed] {
        entries.reduce(into: []) { needs, entry in
            guard let template = entry.item.machine else { return }
            let kind = template.spec.source.consent
            if !needs.contains(where: { $0.kind == kind }) {
                needs.append(SourceNeed(kind: kind, machine: entry.machine.name, reason: template.detail))
            }
        }
    }

    /// Why each item cannot start with what the app has, in the order of the items. An item that follows the facts of a
    /// machine that keeps facts is left out when no item of the template that keeps facts can start.
    func refusals(having: Set<GalleryTemplate.Need>) -> [GalleryStartError?] {
        var refusals = entries.map { $0.item.refusal(having: having) }
        let keeperStarts = zip(entries, refusals).contains { $1 == nil && $0.item.machine?.spec.keepsFacts == true }
        for (index, entry) in entries.enumerated()
        where refusals[index] == nil && entry.item.machine?.spec.needsFollowed == true && !keeperStarts {
            refusals[index] = .nothingToFollow(template: entry.item.name)
        }
        return refusals
    }

    /// The places of the items in the order they start: those that follow another machine's facts come after the rest,
    /// so what they follow is there first. Items otherwise keep their order.
    var startOrder: [Int] {
        let follows = { (index: Int) in entries[index].item.machine?.spec.needsFollowed == true }
        return entries.indices.filter { !follows($0) } + entries.indices.filter(follows)
    }

    var entries: [(machine: TeamMachine, item: GalleryTemplate)] {
        machines.compactMap { machine in GalleryTemplate.of(id: machine.template).map { (machine, $0) } }
    }
}

/// A kind of source a team template needs, and why: the first machine that reads it and what that machine says it does.
public struct SourceNeed: Sendable, Equatable {
    public let kind: SourceKind
    public let machine: String
    public let reason: String
}

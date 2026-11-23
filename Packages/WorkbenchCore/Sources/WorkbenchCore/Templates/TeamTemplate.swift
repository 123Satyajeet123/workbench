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

/// One machine a team template makes: the machine template's id, the machine's name, and what the team changes.
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

/// How a team starts, as data: the kinds of work object it tracks and the machines it makes. A new kind of team is
/// a new value of this type, never new code.
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
    public var watchesCompanies: Bool { seeds.contains { $0.spec.source == .news } }

    /// The machines to make, each with its spec set. A machine whose template is unknown is left out.
    public var seeds: [(spec: HelperSpec, name: String)] {
        known.map { ($0.machine.overrides.applied(to: $0.template.spec), $0.machine.name) }
    }

    /// The kinds of source the machines read, each once, in the order the machines first need them.
    public var sources: [SourceKind] { sourceNeeds.map(\.kind) }

    /// Each kind of source the machines read, with the first machine that needs it and the reason that machine gives.
    public var sourceNeeds: [SourceNeed] {
        known.reduce(into: []) { needs, entry in
            let kind = entry.template.spec.source.kind
            if !needs.contains(where: { $0.kind == kind }) {
                needs.append(SourceNeed(kind: kind, machine: entry.machine.name, reason: entry.template.detail))
            }
        }
    }

    private var known: [(machine: TeamMachine, template: MachineTemplate)] {
        machines.compactMap { machine in MachineTemplate.of(id: machine.template).map { (machine, $0) } }
    }
}

/// A kind of source a team template needs, and why: the first machine that reads it and what that machine says it does.
public struct SourceNeed: Sendable, Equatable {
    public let kind: SourceKind
    public let machine: String
    public let reason: String
}

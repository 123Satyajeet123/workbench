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

    public init(id: String, name: String, purpose: String, objectTypes: [ObjectType], machines: [TeamMachine]) {
        self.id = id
        self.name = name
        self.purpose = purpose
        self.objectTypes = objectTypes
        self.machines = machines
    }

    /// The machines to make, each with its spec set. A machine whose template is unknown is left out.
    public var seeds: [(spec: HelperSpec, name: String)] {
        machines.compactMap { machine in
            MachineTemplate.of(id: machine.template).map { (machine.overrides.applied(to: $0.spec), machine.name) }
        }
    }

    /// The kinds of source the machines read, each once, in the order the machines first need them.
    public var sources: [SourceKind] {
        seeds.map(\.spec.source.kind).reduce(into: []) { kinds, kind in
            if !kinds.contains(kind) { kinds.append(kind) }
        }
    }
}

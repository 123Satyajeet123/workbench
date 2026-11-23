import Foundation

/// A container the person may choose, with every source that saw it.
public struct ContainerCandidate: Sendable, Equatable, Identifiable {
    public var container: Container
    /// The keys of the sources that saw it, in the order they were first merged.
    public var seenBy: [String]
    /// The newest membership any source gave.
    public var membership: Membership?

    public var id: String { container.id }
}

public enum ContainerCandidates {
    /// One candidate for each container id, in the order the ids first appear. The title is the first non-empty one; the
    /// membership is the one observed last.
    public static func merge(_ sightings: [ContainerSighting]) -> [ContainerCandidate] {
        var order: [String] = []
        var merged: [String: ContainerCandidate] = [:]
        var observed: [String: Date] = [:]
        for sighting in sightings {
            let id = sighting.container.id
            guard var candidate = merged[id] else {
                order.append(id)
                merged[id] = ContainerCandidate(
                    container: sighting.container, seenBy: [sighting.source], membership: sighting.membership)
                observed[id] = sighting.membership == nil ? nil : sighting.observedAt
                continue
            }
            if !candidate.seenBy.contains(sighting.source) { candidate.seenBy.append(sighting.source) }
            if candidate.container.title.isEmpty { candidate.container.title = sighting.container.title }
            if let membership = sighting.membership, observed[id].map({ sighting.observedAt > $0 }) ?? true {
                candidate.membership = membership
                observed[id] = sighting.observedAt
            }
            merged[id] = candidate
        }
        return order.compactMap { merged[$0] }
    }
}

/// Which chats a several-chat machine reads, as the founder put it: groups whose name holds some words, and the direct
/// chats with people in those groups.
public struct ChatSelection: Codable, Sendable, Equatable {
    public var nameContains: String
    public var directWithMembers: Bool

    public init(nameContains: String, directWithMembers: Bool) {
        self.nameContains = nameContains
        self.directWithMembers = directWithMembers
    }

    /// The candidates this rule chooses, groups first. It works over every source's candidates: a direct chat counts
    /// when its id is among the members that some source gave for a chosen group.
    public func choose(from candidates: [ContainerCandidate]) -> [ContainerCandidate] {
        let words = nameContains.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return [] }
        let groups = candidates.filter {
            $0.container.kind == .group && $0.container.title.localizedCaseInsensitiveContains(words)
        }
        guard directWithMembers, !groups.isEmpty else { return groups }
        let people = Set(groups.flatMap { $0.membership?.members ?? [] })
        return groups + candidates.filter { $0.container.kind == .direct && people.contains($0.container.id) }
    }
}

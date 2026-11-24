import Foundation
import GRDB

/// The folders and their parents, for choosing between things that sit in different folders. A team is a folder that
/// carries a team key, set when `addTeam` made it: what sits inside it is its own, and never answers for what sits in
/// another team. A folder a person made, nested or not, is never a team. What sits in no team belongs to the workspace
/// itself.
public struct FolderTree: Sendable, Equatable {
    private let parents: [WorkObjectID: WorkObjectID?]
    private let teams: Set<WorkObjectID>

    public init(parents: [WorkObjectID: WorkObjectID?] = [:], teams: Set<WorkObjectID> = []) {
        self.parents = parents
        self.teams = teams
    }

    /// The key of a team's folder. A colon is in it and in no key of a gallery template, and the folder's own id makes
    /// it differ from the key of every other team, also one made from the same template.
    static func teamKey(template: String, folder: WorkObjectID) -> String { "\(teamKeyPrefix)\(template):\(folder)" }

    /// `folder` and the folders above it, nearest first. Empty when `folder` is nil or is no folder.
    public func lineage(of folder: WorkObjectID?) -> [WorkObjectID] {
        var lineage: [WorkObjectID] = []
        var next = folder
        while let current = next, let parent = parents[current], !lineage.contains(current) {
            lineage.append(current)
            next = parent
        }
        return lineage
    }

    /// The team a folder sits in: the nearest folder above it, or itself, that carries a team key. Nil for the
    /// workspace itself.
    public func team(of folder: WorkObjectID?) -> WorkObjectID? { lineage(of: folder).first(where: teams.contains) }

    /// The first of `candidates` that sits nearest to `folder`: in the folder itself, else anywhere below its parent,
    /// and so up to the top folder. Nil when none sits in the folders above `folder`.
    public func nearest<Candidate>(
        in candidates: [Candidate], to folder: WorkObjectID?, folderOf: (Candidate) -> WorkObjectID?
    ) -> Candidate? {
        for level in lineage(of: folder) {
            if let found = candidates.first(where: { lineage(of: folderOf($0)).contains(level) }) { return found }
        }
        return nil
    }

    /// The first of `candidates` that sits in the same team as `folder`, or, for a folder of the workspace itself, among
    /// the things of the workspace itself.
    public func firstSharingTeam<Candidate>(
        in candidates: [Candidate], with folder: WorkObjectID?, folderOf: (Candidate) -> WorkObjectID?
    ) -> Candidate? {
        let wanted = team(of: folder)
        return candidates.first { team(of: folderOf($0)) == wanted }
    }

    /// The nearest of `candidates` to `folder`, else the first of its team.
    public func nearestOrFirstSharingTeam<Candidate>(
        in candidates: [Candidate], with folder: WorkObjectID?, folderOf: (Candidate) -> WorkObjectID?
    ) -> Candidate? {
        nearest(in: candidates, to: folder, folderOf: folderOf)
            ?? firstSharingTeam(in: candidates, with: folder, folderOf: folderOf)
    }
}

extension FolderTree {
    static func read(_ db: Database) throws -> FolderTree {
        let rows = try Row.fetchAll(
            db, sql: "SELECT id, parent_id, start_key FROM work_object WHERE type = ?",
            arguments: [ObjectTypes.folder.id])
        return FolderTree(
            parents: Dictionary(uniqueKeysWithValues: rows.map { ($0["id"] as WorkObjectID, $0["parent_id"]) }),
            teams: Set(
                rows.filter { ($0["start_key"] as String?)?.hasPrefix(teamKeyPrefix) == true }.map { $0["id"] }))
    }

    private static let teamKeyPrefix = "team:"
}

extension Queries {
    public func folderTree() throws -> FolderTree { try reader.read(FolderTree.read) }
}

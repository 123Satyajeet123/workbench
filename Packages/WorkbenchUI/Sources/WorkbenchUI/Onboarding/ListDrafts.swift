import Foundation
import WorkbenchCore

/// The rows of a news feed list while a person edits them. `feeds` is nil until every row is sound.
struct FeedsDraft: Equatable {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var address: String
        var trusted: Bool
    }

    var rows: [Row]

    init(_ feeds: [NewsFeed]) {
        rows = feeds.map { Row(name: $0.name, address: $0.url.absoluteString, trusted: $0.trusted) }
    }

    mutating func add() { rows.append(Row(name: "", address: "", trusted: false)) }
    mutating func remove(_ row: Row) { rows.removeAll { $0.id == row.id } }

    var feeds: [NewsFeed]? {
        let feeds = rows.compactMap { row in
            Self.address(row.address).flatMap { url in
                row.name.cleaned.map { NewsFeed(name: $0, url: url, trusted: row.trusted) }
            }
        }
        return feeds.count == rows.count ? feeds : nil
    }

    var problem: String? {
        feeds == nil ? "Each feed needs a name and a web address that starts with https." : nil
    }

    private static func address(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme == "https", url.host() != nil
        else { return nil }
        return url
    }
}

/// The rows of a claim type list while a person edits them. `types` is nil until the list is sound. A type that was
/// in the list keeps its id; a new one gets an id from its label.
struct ClaimTypesDraft: Equatable {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var typeID: String?
        var label: String
        var proof: String
    }

    var rows: [Row]

    init(_ types: [ClaimType]) {
        rows = types.map { Row(typeID: $0.id, label: $0.label, proof: $0.proof) }
    }

    mutating func add() { rows.append(Row(typeID: nil, label: "", proof: "")) }
    mutating func remove(_ row: Row) { rows.removeAll { $0.id == row.id } }

    var types: [ClaimType]? {
        let types = rows.compactMap { row in
            guard let label = row.label.cleaned, let proof = row.proof.cleaned else { return ClaimType?.none }
            return ClaimType(id: row.typeID ?? Self.id(of: label), label: label, proof: proof)
        }
        guard types.count == rows.count, !types.isEmpty, Set(types.map(\.id)).count == types.count else { return nil }
        return types
    }

    var problem: String? {
        types == nil ? "Each claim type needs a different label and words on what counts as proof." : nil
    }

    private static func id(of label: String) -> String {
        label.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: "_")
    }
}

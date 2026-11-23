import Foundation

/// How the app picks the items it asks the founder about. Each new item is picked on its own, with the same chance, so
/// every answer stands for the same number of items and no reading is over- or under-represented.
public enum AuditPolicy {
    public static let pickChance = 0.15

    /// Picks any item with `pickChance`, whatever its index in its reading.
    @Sendable public static func picks(_ index: Int) -> Bool { Double.random(in: 0..<1) < pickChance }
}

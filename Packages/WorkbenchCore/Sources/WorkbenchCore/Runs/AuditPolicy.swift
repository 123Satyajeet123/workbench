import CryptoKit
import Foundation

/// How the app picks the items it asks the founder about. Each new item is picked on its own, with the same chance, so
/// every answer stands for the same number of items and no reading is over- or under-represented.
public enum AuditPolicy {
    /// The audit design of a task: its name and the version of the way it picks.
    public static func design(of task: String) -> String { "\(task)/audit-v1" }

    /// Whether the item is picked, with `chance`. The pick is a function of the design and the item's store id
    /// only: the same pair always gives the same answer, and the item's content never takes part.
    public static func pick(
        design: String, item: Int64, chance: Double = RunSettings.standard.pickChance
    ) -> Bool {
        uniform(design: design, item: item) < chance
    }

    /// A number in 0..<1 from the first 53 bits of the SHA-256 of the design and the item id.
    static func uniform(design: String, item: Int64) -> Double {
        let digest = SHA256.hash(data: Data("\(design)\n\(item)".utf8))
        let bits = digest.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Double(bits >> 11) / Double(1 << 53)
    }
}

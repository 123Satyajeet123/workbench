import Foundation
import GRDB
import Lines

extension EvidenceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .consentWithdrawn: "The chat is no longer allowed."
        case .erasureNamesNothing: "An erasure must name a source, a grant or an age."
        case .audienceNotAgreed:
            "The people in this group are not the ones who agreed. Ask everyone again, then confirm."
        }
    }
}

extension Store {
    /// The state key of the audience a person confirmed for one chat.
    static func agreementKey(grantID: String) -> String { "agreed." + grantID }

    static func agreement(_ audience: AudienceDigest) -> String { Data(audience.bytes).base64EncodedString() }

    static func agreedAudience(grantID: String, in db: Database) throws -> String? {
        try String.fetchOne(
            db, sql: "SELECT value FROM state WHERE key = ?", arguments: [agreementKey(grantID: grantID)])
    }

    /// Records that everyone in the chat agreed, for this audience and no other. A source whose descriptor requires it
    /// writes lines only for this audience; an erasure of the chat removes the record with the lines.
    public func agree(audience: AudienceDigest, kind: SourceKind, label: String) throws {
        let grant = Self.grantID(kind: kind, label: label)
        try saveState(Self.agreement(audience), forKey: Self.agreementKey(grantID: grant))
    }
}

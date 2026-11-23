import Foundation

extension Schema {
    /// A message that its source said was deleted for good, noted before the erase is written, so a deletion is not lost
    /// while the writer cannot run (the app is starting, or the owner is not known yet). It holds the chat's grant and
    /// the source's own message id, never words, and a row goes when it is applied or when its chat is erased.
    static let pendingRevokes = [
        """
        CREATE TABLE pending_revoke(
            grant_id TEXT NOT NULL CHECK(grant_id <> ''), message_ref TEXT NOT NULL CHECK(message_ref <> ''),
            at INTEGER NOT NULL, PRIMARY KEY(grant_id, message_ref)
        ) STRICT, WITHOUT ROWID
        """
    ]
}

import Foundation

extension Schema {
    /// Both full-text indexes remove the entries of a deleted or changed row when it goes, so the index no longer holds
    /// the old words (the FTS5 option `secure-delete`, SQLite 3.42 or later; sqlite.org/fts5.html). The option is kept in
    /// each index's own `_config` table. It guards against a reader of the index through SQL; `PRAGMA secure_delete`,
    /// which every connection sets, guards against a reader of the file. No row changes: rows written before this step
    /// keep their entries until the next merge removes them.
    static let secureSearch = [
        "INSERT INTO evidence_fts(evidence_fts, rank) VALUES('secure-delete', 1)",
        "INSERT INTO item_fts(item_fts, rank) VALUES('secure-delete', 1)",
    ]
}

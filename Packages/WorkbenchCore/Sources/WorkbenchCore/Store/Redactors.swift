import Foundation
import GRDB

/// What empties the words of one kind of node: the tables it knows, and one function. `wentOut` says the node lost every
/// premise that held it, so its row is flagged as well as emptied. A node that is reached and stays IN loses the words a
/// model wrote and keeps its place, its marks and its quote.
struct Redactor: Sendable {
    var kind: NodeKind
    var tables: [String]
    var redact: @Sendable (_ ids: [DatabaseValue], _ wentOut: Bool, _ db: Database) throws -> Void
}

/// The one way a redactor puts the marker where words were. A row stays, with its marker in every column that held words;
/// only a column that a CHECK ties to a flag (the quote of a fact, the quote of an event) is empty, and a rebuilt copy
/// (a summary) is deleted.
enum Redaction {
    static let marker = "[erased]"

    /// Runs `update`, which binds the marker as `?` or `?1`, on the rows whose key is one of `ids`.
    static func put(_ update: String, into ids: [DatabaseValue], key: String = "id", in db: Database) throws {
        let joiner = update.contains("WHERE") ? " AND " : " WHERE "
        try db.execute(
            sql: update + joiner + "\(key) IN (SELECT value FROM json_each(?2))",
            arguments: [marker, ids.jsonArray])
    }
}

/// The one registry: a redactor for each kind of node that holds words. A table that holds words and has no redactor
/// here fails the manifest check, so a new table cannot leave words behind an erase unseen.
enum Redactors {
    static let all: [Redactor] = [
        Redactor(
            kind: .item,
            tables: [
                "item", "item_fts", "item_fts_config", "item_fts_content", "item_fts_data", "item_fts_docsize",
                "item_fts_idx",
            ],
            redact: { ids, wentOut, db in
                let list = ids.jsonArray
                if wentOut {
                    try db.execute(
                        sql:
                            "UPDATE item SET quote = '', source_deleted = 1 WHERE id IN (SELECT value FROM json_each(?))",
                        arguments: [list])
                }
                try Store.emptyModelWords(ofItems: list, in: db)
            }),
        Redactor(
            kind: .itemEvent, tables: ["item_event"],
            redact: { ids, _, db in
                try db.execute(
                    sql: """
                        UPDATE item_event SET quote = '' WHERE actor = 'model' AND quote <> ''
                            AND id IN (SELECT value FROM json_each(?))
                        """, arguments: [ids.jsonArray])
            }),
        Redactor(
            kind: .summary, tables: ["summary"],
            redact: { ids, _, db in try Store.removeSummaries(db, keys: ids.compactMap(String.fromDatabaseValue)) }),
        Redactor(
            kind: .machineBlock, tables: ["machine_block"],
            redact: { ids, _, db in try Store.emptyWords(ofBlocks: ids.compactMap(String.fromDatabaseValue), in: db) }),
        Redactor(
            kind: .pageProposal, tables: ["page_proposal"],
            redact: { ids, _, db in try Redaction.put("UPDATE page_proposal SET note = ?", into: ids, in: db) }),
        Redactor(
            kind: .run, tables: ["run", "run_text", "drop_reason"],
            redact: { ids, _, db in
                try Redaction.put("UPDATE run SET error = ? WHERE error IS NOT NULL", into: ids, key: "id", in: db)
                try Redaction.put(
                    "UPDATE run_text SET input = ?1, reply = CASE WHEN reply IS NULL THEN NULL ELSE ?1 END", into: ids,
                    key: "run_id", in: db)
                try Redaction.put(
                    "UPDATE drop_reason SET proposal = json_quote(?)", into: ids, key: "run_id", in: db)
            }),
        Redactor(
            kind: .proposal, tables: ["proposal"],
            redact: { ids, _, db in
                try Redaction.put(
                    "UPDATE proposal SET name = ?1, brief = ?1, why = ?1, evidence = '[]'", into: ids, in: db)
            }),
        Redactor(
            kind: .workProduct, tables: ["work_product"],
            redact: { ids, _, db in try Redaction.put("UPDATE work_product SET text = ?", into: ids, in: db) }),
        Redactor(
            kind: .claimCite, tables: ["claim_cite"],
            redact: { ids, _, db in try Redaction.put("UPDATE claim_cite SET quote = ?", into: ids, in: db) }),
        Redactor(
            kind: .judgeVerdict, tables: ["judge_verdict"],
            redact: { ids, _, db in
                try Redaction.put("UPDATE judge_verdict SET reason = ?1, detail = ?1", into: ids, in: db)
            }),
        Redactor(
            kind: .productMark, tables: ["product_mark"],
            redact: { ids, _, db in
                try Redaction.put(
                    "UPDATE product_mark SET edited_text = ? WHERE edited_text IS NOT NULL", into: ids, in: db)
            }),
        Redactor(
            kind: .action, tables: ["action"],
            redact: { ids, _, db in try Redaction.put("UPDATE action SET detail = json_quote(?)", into: ids, in: db) }),
        Redactor(
            kind: .machineDecision, tables: ["machine_decision"],
            redact: { ids, _, db in
                try Redaction.put(
                    "UPDATE machine_decision SET brief = ?1, parent_brief = ?1, detail = json_quote(?1)", into: ids,
                    in: db)
            }),
        Redactor(
            kind: .workEvent, tables: ["work_event"],
            redact: { ids, _, db in
                try Redaction.put(
                    """
                    UPDATE work_event SET body = json_set(body, '$.item.quote', ?1, '$.item.fields',
                        json((SELECT json_group_object(key, ?1) FROM json_each(body, '$.item.fields'))))
                    WHERE json_type(body, '$.item') = 'object'
                    """, into: ids, in: db)
            }),
        Redactor(
            kind: .line,
            tables: [
                "evidence", "evidence_fts", "evidence_fts_config", "evidence_fts_data", "evidence_fts_docsize",
                "evidence_fts_idx",
            ],
            redact: { ids, _, db in
                for id in ids { try db.execute(sql: "DELETE FROM evidence WHERE line_id = ?", arguments: [id]) }
            }),
        Redactor(
            kind: .snapshot, tables: ["page_snapshot"],
            redact: { ids, _, db in
                try db.execute(
                    sql: "DELETE FROM page_snapshot WHERE id IN (SELECT value FROM json_each(?))",
                    arguments: [ids.jsonArray])
            }),
        Redactor(
            kind: .activity, tables: ["activity"],
            redact: { ids, _, db in
                try db.execute(
                    sql: "DELETE FROM activity WHERE id IN (SELECT value FROM json_each(?))", arguments: [ids.jsonArray]
                )
            }),
        Redactor(
            kind: .mailPart, tables: ["mail_part"],
            redact: { ids, _, db in
                try db.execute(
                    sql: "DELETE FROM mail_part WHERE id IN (SELECT value FROM json_each(?))",
                    arguments: [ids.jsonArray])
            }),
        Redactor(
            kind: .newsArticle, tables: ["news_article"],
            redact: { ids, _, db in
                try db.execute(
                    sql: "DELETE FROM news_article WHERE id IN (SELECT value FROM json_each(?))",
                    arguments: [ids.jsonArray])
            }),
        Redactor(
            kind: .recording, tables: ["recording"],
            redact: { ids, _, db in
                try db.execute(
                    sql: "DELETE FROM recording WHERE id IN (SELECT value FROM json_each(?))",
                    arguments: [ids.jsonArray])
            }),
    ]
}

extension [DatabaseValue] {
    /// The ids as a JSON array, for `json_each`: row numbers and text keys.
    fileprivate var jsonArray: String {
        let values: [Any] = map { value in
            switch value.storage {
            case .int64(let number): number
            case .string(let text): text
            default: NSNull()
            }
        }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: values)) ?? Data("[]".utf8), as: UTF8.self)
    }
}

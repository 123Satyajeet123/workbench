import Foundation

extension Schema {
    /// Search over the words of facts. `item_fts` holds, for each item, the values of the fields of its machine that
    /// are free text, and its title field: never a member, choice, date or label field, so no person id is indexed.
    /// Its row number is the item's id. Triggers keep it in step with every insert, update and delete of an item,
    /// the erase of copies included, and the step builds it for the items that exist. The machine is the one the
    /// item's task names, its trial task included, as the machine is now.
    static let itemSearch = [
        """
        CREATE VIRTUAL TABLE item_fts USING fts5(
            words, tokenize = "unicode61 categories 'L* N* Co Mn Mc' tokenchars '\u{200C}\u{200D}'")
        """,
        """
        CREATE TRIGGER item_fts_insert AFTER INSERT ON item
        BEGIN INSERT INTO item_fts(rowid, words) SELECT new.id, \(itemWords(of: "new")); END
        """,
        """
        CREATE TRIGGER item_fts_update AFTER UPDATE OF task, fields ON item
        BEGIN
            DELETE FROM item_fts WHERE rowid = old.id;
            INSERT INTO item_fts(rowid, words) SELECT new.id, \(itemWords(of: "new"));
        END
        """,
        """
        CREATE TRIGGER item_fts_delete AFTER DELETE ON item
        BEGIN DELETE FROM item_fts WHERE rowid = old.id; END
        """,
        "INSERT INTO item_fts(rowid, words) SELECT item.id, \(itemWords(of: "item")) FROM item",
    ]

    private static func itemWords(of row: String) -> String {
        """
        COALESCE((SELECT group_concat(value.value, ' ') FROM machine_now machine,
            json_each(machine.spec, '$.fields') field, json_each(\(row).fields) value
            WHERE (machine.task = \(row).task OR machine.task || '#trial' = \(row).task)
                AND value.key = json_extract(field.value, '$.name')
                AND (json_extract(field.value, '$.kind.text') IS NOT NULL
                    OR value.key = json_extract(machine.spec, '$.title'))), '')
        """
    }
}

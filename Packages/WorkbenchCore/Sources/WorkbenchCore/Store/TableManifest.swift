import Foundation

/// Whether a table of the schema holds words that a source gave, and which redactor empties them. A table that holds
/// words names the kind of its redactor (`Redactors`); the rest hold ids, numbers, names the person typed, and the text of
/// settings, none of which copies a source. `ProvenanceCheck` fails on a table of the schema that this manifest does not
/// name, and on a table that holds words that its redactor does not list.
enum TableManifest {
    /// The tables that hold words, with the kind of the redactor that owns each: the source tables, the tables derived
    /// from them, and the search indexes, whose shadow tables keep a copy of every word they index.
    static let words: [String: NodeKind] = [
        "evidence": .line, "evidence_fts": .line, "evidence_fts_config": .line, "evidence_fts_data": .line,
        "evidence_fts_docsize": .line, "evidence_fts_idx": .line,
        "page_snapshot": .snapshot, "activity": .activity, "mail_part": .mailPart, "news_article": .newsArticle,
        "recording": .recording,
        "item": .item, "item_fts": .item, "item_fts_config": .item, "item_fts_content": .item, "item_fts_data": .item,
        "item_fts_docsize": .item, "item_fts_idx": .item,
        "item_event": .itemEvent, "summary": .summary, "machine_block": .machineBlock, "page_proposal": .pageProposal,
        "proposal": .proposal, "run": .run, "run_text": .run, "action": .action,
        "work_event": .workEvent, "machine_decision": .machineDecision, "drop_reason": .run,
        "work_product": .workProduct,
        "claim_cite": .claimCite, "judge_verdict": .judgeVerdict, "product_mark": .productMark,
    ]

    /// Ids, keys, hashes, counts and times; the settings and policies; and the text that a person typed or a machine's
    /// own brief, which are not copies of a source. The tables that were read for a path that puts a source's words in them are in `words`: `run.error` (the message of a failed call), `action.detail`, `work_event.body` and `machine_decision`.
    static let noWords: Set<String> = [
        "consent", "container_order", "derivation", "entity_supersede", "evidence_legacy", "evidence_view",
        "fact_link", "handled_batch", "heldout_report", "judge_freeze", "machine", "machine_block_cite",
        "machine_change", "mail_open", "mark", "mark_reason", "member", "member_handle",
        "pending_revoke", "product_claim", "prompt", "proposal_decision", "quote_mark", "run_input",
        "run_window", "sla_policy", "state", "status_change", "team", "timer", "timer_fired", "work_object",
    ]
}

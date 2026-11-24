import Foundation

@testable import WorkbenchCore

/// The instructions of the tools arm: the composer's own text, with only the words about where facts come from
/// changed. What an operation is and what a block is stay as `PageComposer.instructions` says.
enum PageEvalToolInstructions {
    /// Each pair: the words of the composer about where a name or a value comes from, and the words that point at a tool.
    private static let replacements: [(from: String, to: String)] = [
        (
            "facts (F1, F2, …), blocks of the person (B1, …)",
            "facts (F1, F2, …, only handles that `facts` returned), blocks of the person (B1, …, only handles that "
                + "`page` returned)"
        ),
        ("copied exactly from the catalog;", "copied exactly from the catalog that `page` returns;"),
        (
            "copied from the COLUMNS list (quote is the exact words)",
            "copied from the columns that `page` returns (quote is the exact words)"
        ),
    ]

    private static let sourceOfFacts = """
        Your input holds only the request and your job. The page, the catalog and the facts are not in it. You have \
        three read-only tools. Call `page` first: it gives the blocks in order, the cap of machine blocks, the \
        catalog and the columns. Get facts with `facts` (a `filter`, a `groupBy`, the `fields` you need, a `limit`). \
        Get every number with `count`; never count facts yourself. Name only a handle (F…, B…) that a tool returned. \
        Call only the tools the request needs.

        """

    static let text: String = {
        let changed = replacements.reduce(PageComposer.instructions) { text, pair in
            precondition(text.components(separatedBy: pair.from).count == 2, "not found once: \(pair.from)")
            return text.replacingOccurrences(of: pair.from, with: pair.to)
        }
        let anchor = "Do what the request asks and no more."
        precondition(changed.components(separatedBy: anchor).count == 2, "not found once: \(anchor)")
        return changed.replacingOccurrences(of: anchor, with: sourceOfFacts + anchor)
    }()
}

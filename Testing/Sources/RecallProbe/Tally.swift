import Foundation
import WorkbenchCore

/// A kept item, as the tally and the gleaning pass need it: its line, its fields and its words.
struct Kept: Codable {
    let line: Int64
    let fields: [String: String]
    let quote: String

    init(_ item: Item) {
        line = item.citeFirst
        fields = item.fields
        quote = item.quote
    }

    var kind: String { fields["kind"] ?? "" }
    var person: String { fields["person"] ?? "" }

    /// The item again, for a later pass to list and to compare with `SameClaim`.
    func item(task: String, day: SyntheticDay) -> Item {
        let start = day.evidence.lines.first { $0.id == line }?.start ?? day.day.start
        return Item(
            task: task, day: day.day, scope: "synthetic", source: .whatsapp, citeFirst: line, citeLast: line,
            start: start, end: start, fields: fields, quote: quote, run: nil)
    }
}

/// The arms: today's read (A), A plus one gleaning pass (B, which saves only what the pass adds), the read with the
/// founder sentence in the brief (C), and today's read with the founder named by plain name in the lines and the
/// members list (D, added after the drops showed the "(You)" label at work).
enum Arm: String, CaseIterable, Codable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
}

/// One model pass of one arm on one day. Saved as JSON, so a pass that finished is never asked again.
struct Reading: Codable {
    let day: Int
    let arm: Arm
    let run: Int
    let model: String
    let kept: [Kept]
    let drops: [String]
    let usage: Usage
}

/// How a needle fared in one reading, matched by code: the line an item cites and the kind and person it gives.
struct Outcome {
    let needle: Needle
    let strict: Bool
    let line: Bool
    let personRight: Bool
    /// The kinds the reading gave on the needle's line.
    let kinds: [String]

    init(_ needle: Needle, line number: Int64, items: [Kept]) {
        self.needle = needle
        let onLine = items.filter { $0.line == number }
        kinds = onLine.map(\.kind)
        line = !onLine.isEmpty
        strict = kinds.contains(needle.kind.rawValue)
        personRight = onLine.contains { $0.kind == needle.kind.rawValue && $0.person == needle.person.rawValue }
    }
}

/// Share as "found/total (percent)".
func share(_ found: Int, of total: Int) -> String {
    total == 0 ? "0/0" : "\(found)/\(total) (\(String(format: "%.1f", 100 * Double(found) / Double(total)))%)"
}

func dollars(_ value: Double) -> String { String(format: "%.4f USD", value) }

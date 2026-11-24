import Foundation
import WorkbenchCore

/// A kept item, as the tally needs it: its line, its kind and its words.
struct Kept: Codable {
    let line: Int64
    let kind: String
    let person: String
    let text: String
    let quote: String

    init(_ item: Item) {
        line = item.citeFirst
        kind = item["kind"]
        person = item["person"]
        text = item["text"]
        quote = item.quote
    }
}

/// One run of one day: the first reading (arm A) and its gleaning pass. Arm B is both together. Saved as JSON, so a
/// run that finished is never asked again.
struct DayRun: Codable {
    let day: Int
    let run: Int
    let model: String
    let first: [Kept]
    let firstDrops: [String]
    let firstUsage: Usage
    let gleaned: [Kept]
    let gleanDrops: [String]
    let gleanUsage: Usage

    func items(_ arm: Arm) -> [Kept] { arm == .a ? first : first + gleaned }

    /// Gleaned items on a line where the first reading already kept an item of the same kind, in other words.
    var nearRepeats: Int {
        gleaned.filter { new in first.contains { $0.line == new.line && $0.kind == new.kind } }.count
    }
}

enum Arm: String, CaseIterable {
    case a = "A"
    case b = "B"
}

/// How a needle fared in one arm of one run, matched by code: the line an item cites and the kind it gives.
struct Outcome {
    let needle: Needle
    let strict: Bool
    let line: Bool
    /// The kinds the arm gave on the needle's line.
    let kinds: [String]

    init(_ needle: Needle, line number: Int64, items: [Kept]) {
        self.needle = needle
        kinds = items.filter { $0.line == number }.map(\.kind)
        line = !kinds.isEmpty
        strict = kinds.contains(needle.kind.rawValue)
    }
}

extension DayRun {
    func outcomes(_ arm: Arm, on day: SyntheticDay) -> [Outcome] {
        day.needles.map { Outcome($0.needle, line: $0.line, items: items(arm)) }
    }

    func otherLines(_ items: [Kept], on day: SyntheticDay) -> Int {
        let needles = Set(day.needles.map(\.line))
        return items.filter { !needles.contains($0.line) }.count
    }
}

/// Share as "found of total (percent)".
func share(_ found: Int, of total: Int) -> String {
    total == 0 ? "0 of 0" : "\(found) of \(total) (\(String(format: "%.1f", 100 * Double(found) / Double(total)))%)"
}

func dollars(_ value: Double) -> String { String(format: "%.4f USD", value) }

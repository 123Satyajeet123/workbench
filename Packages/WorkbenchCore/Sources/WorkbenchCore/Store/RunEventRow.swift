import Foundation
import GRDB

/// A `RunEvent` as the columns of `run_event` keep it. The columns that an event does not use are nil.
struct RunEventRow: Equatable {
    var kind: String
    var lines: Int?
    var parts: Int?
    var part: Int?
    var partRun: RunID?
    var count: Int?
    var tag: String?
    var byRule: String?
    var cost: String?

    init(_ event: RunEvent) throws {
        switch event {
        case .started(let lines, let parts, let promptHash):
            self.init(kind: "started", lines: lines, parts: parts, tag: promptHash)
        case .partRead(let number, let lines, let run):
            self.init(kind: "part_read", lines: lines, part: number, partRun: run)
        case .proposed(let count): self.init(kind: "proposed", count: count)
        case .kept(let count): self.init(kind: "kept", count: count)
        case .dropped(let reasons):
            self.init(
                kind: "dropped",
                byRule: try Coding.json(Dictionary(uniqueKeysWithValues: reasons.map { ($0.key.rawValue, $0.value) })))
        case .capHit(let cap, let leftOut): self.init(kind: "cap_hit", count: leftOut, tag: cap.rawValue)
        case .filed(let count): self.init(kind: "filed", count: count)
        case .asked(let count): self.init(kind: "asked", count: count)
        case .failed(let reason): self.init(kind: "failed", tag: reason.rawValue)
        case .cancelled: self.init(kind: "cancelled")
        case .finished(let cost): self.init(kind: "finished", cost: try Coding.json(cost))
        }
    }

    init(row: Row) throws {
        self.init(
            kind: try row.value("kind"), lines: try row.optionalValue("lines"), parts: try row.optionalValue("parts"),
            part: try row.optionalValue("part"), partRun: try row.optionalValue("part_run"),
            count: try row.optionalValue("count"), tag: try row.optionalValue("tag"),
            byRule: try row.optionalValue("by_rule"), cost: try row.optionalValue("cost"))
    }

    private init(
        kind: String, lines: Int? = nil, parts: Int? = nil, part: Int? = nil, partRun: RunID? = nil,
        count: Int? = nil, tag: String? = nil, byRule: String? = nil, cost: String? = nil
    ) {
        self.kind = kind
        self.lines = lines
        self.parts = parts
        self.part = part
        self.partRun = partRun
        self.count = count
        self.tag = tag
        self.byRule = byRule
        self.cost = cost
    }

    /// The event these columns keep. Columns that do not fit the kind, or a name that is not a closed name, throw.
    func event() throws -> RunEvent {
        switch kind {
        case "started":
            .started(lines: try need(lines, "lines"), parts: try need(parts, "parts"), promptHash: try need(tag, "tag"))
        case "part_read": .partRead(number: try need(part, "part"), lines: try need(lines, "lines"), run: partRun)
        case "proposed": .proposed(try need(count, "count"))
        case "kept": .kept(try need(count, "count"))
        case "dropped": .dropped(try dropRules())
        case "cap_hit": .capHit(try closed(tag, "tag"), leftOut: try need(count, "count"))
        case "filed": .filed(try need(count, "count"))
        case "asked": .asked(try need(count, "count"))
        case "failed": .failed(try closed(tag, "tag"))
        case "cancelled": .cancelled
        case "finished": .finished(try Coding.value(RunCost.self, from: try need(cost, "cost")))
        default: throw StoredValueError("kind")
        }
    }

    private func need<T>(_ value: T?, _ column: String) throws -> T {
        guard let value else { throw StoredValueError(column) }
        return value
    }

    private func closed<Name: RawRepresentable>(_ text: String?, _ column: String) throws -> Name
    where Name.RawValue == String {
        guard let name = Name(rawValue: try need(text, column)) else { throw StoredValueError(column) }
        return name
    }

    private func dropRules() throws -> [DropRule: Int] {
        let counts = try Coding.value([String: Int].self, from: try need(byRule, "by_rule"))
        return Dictionary(
            uniqueKeysWithValues: try counts.map { name, count in
                guard let rule = DropRule(rawValue: name) else { throw StoredValueError("by_rule") }
                return (rule, count)
            })
    }
}

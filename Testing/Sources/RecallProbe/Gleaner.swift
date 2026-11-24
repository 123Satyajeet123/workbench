import Foundation

@testable import WorkbenchCore

/// One add-only pass after a reading (research T3 probe 2, the GraphRAG "gleaning" form): the same reader's
/// instructions and schema with one more rule, the items the reading kept listed before the day, and the same lines.
/// Its proposals go through the same `Verifier`; one that `SameClaim` finds among the kept items is a repeat.
struct Gleaner: ModelTask {
    typealias Reply = HelperReader.Reply

    let reader: HelperReader
    let zone: TimeZone

    var task: String { reader.spec.task + ".glean" }
    var model: RecordedModel { reader.model }
    var schema: JSONSchema { reader.schema }
    var instructions: String { reader.instructions + Self.rule }

    static let rule = """


        Before the day, you get the items an earlier reading of these same lines found, each with its line number. \
        Give only the items that list misses: facts the lines state that no listed item holds. Never give a listed \
        item again, in the same or in other words. Return no item when nothing is missing.
        """

    struct Result {
        var items: [Item]
        var drops: [Drop]
        var run: RunID
    }

    func glean(day: WorkDay, scope: String, evidence: EvidenceSet, found: [Item]) async throws -> Result {
        let spec = reader.spec
        let (reply, run) = try await ask(
            Self.listing(found, spec: spec) + HelperReader.input(day: day, evidence: evidence, zone: zone),
            holding: [spec.source.consent],
            window: evidence.lines.compactMap { line in line.lineID.map { WindowLine(number: line.id, lineID: $0) } })
        let verifier = Verifier(window: evidence, settings: try model.verifierSettings(), zone: zone)
        let repeats = { (new: Verifier.Checked, kept: [Item]) in
            kept.contains { SameClaim.holds(new.item, $0, citation: spec.citation, choices: spec.choiceFields) }
        }
        let settled = try verifier.settle(
            reply.items, part: "items",
            check: { try verifier.proposal($0, spec: spec, open: [], day: day, scope: scope, run: run) },
            isRepeat: { repeats($0, found + $1.map(\.item)) })
        try model.record(settled.drops, of: run)
        return Result(items: settled.kept.map(\.item), drops: settled.drops, run: run)
    }

    static func listing(_ found: [Item], spec: HelperSpec) -> String {
        let lines = found.map { "- [\($0.citeFirst)] \(spec.shownValues(of: $0)) — \"\($0.quote)\"" }
        return "Found by the earlier reading:\n" + (lines.isEmpty ? "(nothing)" : lines.joined(separator: "\n"))
            + "\n\n"
    }
}

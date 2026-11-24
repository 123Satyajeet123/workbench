import Foundation

/// The events a reading of a day writes, built from what `HelperReader` returns. Pure: no store, no clock, no model.
extension RunEvent {
    /// The first event of a reading of `evidence` in parts of up to `budget` characters, under the prompt that `promptHash` names.
    public static func start(of evidence: EvidenceSet, budget: Int, promptHash: String) -> RunEvent {
        .started(
            lines: evidence.newLines.count, parts: HelperReader.partSizes(of: evidence, budget: budget).count,
            promptHash: promptHash)
    }

    /// The events of part `number`, which showed the model `lines` new lines. `leftOut` is what each cap hid from
    /// the model in this part.
    public static func events(
        of part: HelperReader.Result, number: Int, lines: Int, leftOut: [RunCap: Int] = [:]
    ) -> [RunEvent] {
        let read = RunEvent.partRead(number: number, lines: lines, run: part.run)
        guard part.run != nil else { return [read] }
        let caps = leftOut.filter { $0.value > 0 }.sorted { $0.key.rawValue < $1.key.rawValue }
        return [read, .proposed(part.proposed), .kept(part.kept)]
            + (part.droppedByRule.isEmpty ? [] : [.dropped(part.droppedByRule)])
            + caps.map { .capHit($0.key, leftOut: $0.value) }
            + (part.homes.isEmpty ? [] : [.filed(part.homes.count)])
    }

    /// The last events of a reading whose model calls are `runs`, and that stopped for `failure`, if it did.
    public static func ending(runs: [Run], failure: Run.Failure? = nil) -> [RunEvent] {
        (failure.map { [.failed($0)] } ?? []) + [.finished(RunCost(of: runs))]
    }
}

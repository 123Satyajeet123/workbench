import Foundation

/// The events a reading of a day writes, built from what `HelperReader` returns. Pure: no store, no clock, no model.
extension RunEvent {
    /// The first event of a reading of `evidence` in parts of up to `budget` characters, under the prompt that `promptHash` names.
    public static func start(of evidence: EvidenceSet, budget: Int, promptHash: String) -> RunEvent {
        .started(
            lines: evidence.newLines.count, parts: HelperReader.partSizes(of: evidence, budget: budget).count,
            promptHash: promptHash)
    }

    /// The events of part `number`, which showed the model `lines` new lines. What a cap hid from the model is a
    /// `capHit`, and is not in `dropped`: `Result.droppedByRule` holds the refused proposals only.
    public static func events(of part: HelperReader.Result, number: Int, lines: Int) -> [RunEvent] {
        let read = RunEvent.partRead(number: number, lines: lines, run: part.run)
        guard part.run != nil else { return [read] }
        let caps = part.leftOut.filter { $0.count > 0 }
        return [read, .proposed(part.proposed), .kept(part.kept)]
            + (part.droppedByRule.isEmpty ? [] : [.dropped(part.droppedByRule)])
            + caps.map { .capHit($0.part, leftOut: $0.count) }
            + (part.homes.isEmpty ? [] : [.filed(part.homes.count)])
    }

    /// The last events of a reading whose model calls are `runs`: how it stopped, if it did, and its cost.
    public static func ending(runs: [Run], stop: RunState.Stop?) -> [RunEvent] {
        let stopped: [RunEvent] =
            switch stop {
            case .failed(let reason): [.failed(reason)]
            case .cancelled: [.cancelled]
            case nil: []
            }
        return stopped + [.finished(RunCost(of: runs))]
    }
}

extension RunState.Stop {
    /// How a reading ended by `error`: the app stopped it, or it failed for the kind its type names, or `other`.
    public init(error: any Error) {
        self = error is CancellationError ? .cancelled : .failed((error as? any ClassifiedFailure)?.failure ?? .other)
    }
}

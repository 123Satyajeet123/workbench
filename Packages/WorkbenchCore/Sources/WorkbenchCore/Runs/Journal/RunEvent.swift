import Foundation

/// One thing a reading did, in the order it did it. A journal is a list of these. Every word the person later reads
/// about a run comes from one event.
///
/// An event holds counts, numbers, typed reasons and ids, and no text of any line, fact, person or model reply. A
/// line a run read is reached through `run_input` under the id of the run; so erasing a line needs no change to a
/// journal. The one `String` is the hash of the prompt's instructions and schema (`Run.prompt`): a digest, not text.
public enum RunEvent: Sendable, Equatable {
    /// The reading begins. `lines` new lines will be read in `parts` parts, with the prompt that `promptHash` names.
    case started(lines: Int, parts: Int, promptHash: String)
    /// Part `number` was read in the model call `run`, which shows its lines under `run_input`. `run` is nil when
    /// no model ran for the part.
    case partRead(number: Int, lines: Int, run: RunID?)
    /// The model made this many proposals for the part.
    case proposed(Int)
    /// The proposals of the part that code kept.
    case kept(Int)
    /// The proposals of the part that code refused, counted by the rule each broke.
    case dropped([DropRule: Int])
    /// A cap hid this many entries from the model in the part.
    case capHit(RunCap, leftOut: Int)
    /// This many facts of the part got a proposed home.
    case filed(Int)
    /// Reserved for the questions step: this many questions were put to the person. Nothing writes it yet.
    case asked(Int)
    /// The reading stopped for this reason.
    case failed(Run.Failure)
    /// The reading ended. Nothing follows.
    case finished(RunCost)
}

/// A cap that hides entries from the model. The cases name the cuts a reading can make.
public enum RunCap: String, Sendable, CaseIterable {
    case openFacts, objects, pageCharacters, memoryEntries
}

/// What the model calls of a reading cost. A call that ended with no count of its cost is counted apart, never as free.
public struct RunCost: Sendable, Equatable {
    public var known: Usage
    public var callsWithoutCost: Int

    public init(known: Usage, callsWithoutCost: Int) {
        self.known = known
        self.callsWithoutCost = callsWithoutCost
    }

    public init(of runs: [Run]) {
        self.init(
            known: runs.compactMap(\.usage).reduce(Usage(), +), callsWithoutCost: runs.filter { $0.usage == nil }.count)
    }

    /// No call has a known cost.
    public var isUnknown: Bool { callsWithoutCost > 0 && known == Usage() }
}

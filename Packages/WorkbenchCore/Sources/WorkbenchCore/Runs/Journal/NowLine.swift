import Foundation

/// The one plain sentence that says what a machine is doing now. It is built from the tail of the journal and the
/// numbers in the state. Code never reads the meaning of a line or of a model reply.
public enum NowLine {
    public static func sentence(of state: RunState, machine: String) -> String {
        let place = "part \(max(state.partsRead, 1)) of \(state.parts)"
        switch state.last {
        case .started(let lines, let parts, _):
            return "\(machine) waits for the model to read part 1 of \(parts) (\(count(lines, "new line")))."
        case .partRead(_, _, nil):
            return "\(machine) had nothing to send to the model for \(place)."
        case .partRead(_, let lines, _):
            return "\(machine) read \(place) (\(count(lines, "line"))). It checks what it found."
        case .proposed(let found):
            return "\(machine) found \(count(found, "item")) in \(place). It checks each one."
        case .kept(let kept):
            return "\(machine) kept \(kept) of \(count(state.part.proposed ?? kept, "item")) in \(place)."
        case .dropped(let reasons):
            return
                "\(machine) kept \(state.part.kept ?? 0) and dropped \(reasons.values.reduce(0, +)) in \(place): \(words(of: reasons))."
        case .capHit(let cap, let leftOut):
            return "\(machine) did not see \(count(leftOut, cap.noun)) in \(place): a limit cut them."
        case .filed(let filed):
            return "\(machine) suggests a home for \(count(filed, "fact")) from \(place)."
        case .asked(let asked):
            return "\(machine) has \(count(asked, "question")) for you."
        case .failed(let reason):
            return stopped(state, stop: .failed(reason), machine: machine)
        case .cancelled:
            return stopped(state, stop: .cancelled, machine: machine)
        case .finished(let cost):
            if let stop = state.stop { return stopped(state, stop: stop, machine: machine) }
            return
                "\(machine) finished. It kept \(state.yield.kept) and dropped \(state.yield.dropped). \(costWords(cost))"
        }
    }

    private static func stopped(_ state: RunState, stop: RunState.Stop, machine: String) -> String {
        let progress = "\(machine) stopped after \(state.partsRead) of \(count(state.parts, "part"))"
        switch stop {
        case .cancelled: return "\(progress), because the app stopped it."
        case .failed(.limit): return "\(progress) and waits. \(Run.Failure.limit.cause)"
        case .failed(let reason): return "\(progress). \(reason.cause)"
        }
    }

    private static func words(of reasons: [DropRule: Int]) -> String {
        let ordered = reasons.sorted { $0.key.rawValue < $1.key.rawValue }
        guard ordered.count > 1 else { return ordered.first?.key.cause ?? "" }
        return ordered.map { "\($0.value) because \($0.key.cause)" }.joined(separator: "; ")
    }

    private static func costWords(_ cost: RunCost) -> String {
        if cost.isUnknown { return "The cost is not known." }
        let spent = cost.known.costUSD
        let amount =
            spent > 0 && spent < 0.01
            ? spent.formatted(.currency(code: "USD").precision(.significantDigits(1...3)))
            : spent.formatted(.currency(code: "USD").precision(.fractionLength(2)))
        return cost.callsWithoutCost == 0
            ? "It cost \(amount)."
            : "It cost \(amount), and \(count(cost.callsWithoutCost, "call")) has no cost figure."
    }

    static func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}

extension LeftOut.Part {
    fileprivate var noun: String {
        switch self {
        case .openFacts: "open fact"
        case .objects: "object"
        case .pageCharacters: "character of the page"
        case .memoryEntries: "memory entry"
        }
    }
}

extension Run.Failure {
    fileprivate var cause: String {
        switch self {
        case .limit: "The plan limit is reached."
        case .timedOut: "The model did not answer in time."
        case .notInstalled: "The model tool is not installed on this Mac."
        case .noAPIKey: "There is no API key."
        case .unsafePlan: "The model call was not safe, so it did not run."
        case .other: "The model call failed."
        }
    }
}

extension DropRule {
    /// The reason in a clause that follows "because" or a colon.
    fileprivate var cause: String {
        switch self {
        case .malformed: "a key was missing or had the wrong type"
        case .outsideWindow: "it cited a line that was not in this part"
        case .quoteNotInLines: "the quote was not in the line"
        case .quoteTooShort: "the quote was too short"
        case .fieldKind: "a value did not fit its field"
        case .unknownHandle: "it named something the model was not shown"
        case .identityMismatch: "it named a fact of another owner"
        case .lineBeforeFact: "its line was older than the fact"
        case .repeatInReading: "it said the same as an earlier item"
        case .noCite: "it had no cite"
        case .sourceMissing: "the cited line or page is not stored"
        case .snapshotChanged: "the stored page changed"
        case .sourceRefused: "the page may not be read"
        case .pageDateMissing: "the page states no date"
        case .factNotCited: "a number, date or name was not in the cited words"
        case .verifierError: "the check could not run"
        case .leftOut: "a limit cut it"
        }
    }
}

import Foundation

/// The sentences for a machine that is not reading, and for what it did before. Each is built from typed facts and
/// dates that code formats in the person's zone. Code never reads the words of a line or of a model reply.
extension NowLine {
    /// The whole sentence of a machine's status: why it does not read, or what it is doing, and what it did before.
    static func sentence(
        machine: String, notReading: [NotReading], latest: RunState?, history: ReadingHistory, nextReading: Date?,
        now: Date, zone: TimeZone
    ) -> String {
        let moments = Moments(zone: zone)
        if let reason = notReading.first {
            return "\(blocked(machine, reason, moments)) \(past(machine, history, moments))"
        }
        let doing = latest.map { sentence(of: $0, machine: machine) } ?? past(machine, history, moments)
        guard let nextReading else { return doing }
        return "\(doing) \(next(nextReading, now: now, moments))"
    }

    /// One sentence for each event of a journal: what `sentence(of:machine:)` says when that event is the last one.
    public static func lines(of events: [RunEvent], machine: String) throws -> [String] {
        try events.indices.map { sentence(of: try RunState.fold(Array(events[...$0])), machine: machine) }
    }

    private static func blocked(_ machine: String, _ reason: NotReading, _ moments: Moments) -> String {
        switch reason {
        case .pausedByPerson: "\(machine) is paused: you paused it."
        case .sourceOff: "\(machine) is not reading: its source is switched off."
        case .nothingChosen: "\(machine) is not reading: nothing is chosen for it to read."
        case .model(.notInstalled): "\(machine) is not reading: the model tool is not installed on this Mac."
        case .model(.termsNotConfirmed):
            "\(machine) is not reading: you have not yet said yes to the conditions of the model."
        case .model(.planLimit(let plan, let until)):
            "\(machine) is paused until \(moments.dayAndTime(until)): the \(plan.capitalized) plan limit is reached."
        }
    }

    private static func past(_ machine: String, _ history: ReadingHistory, _ moments: Moments) -> String {
        switch history {
        case .finished(let last):
            "It last read on \(moments.dayAtTime(last.at)) and kept \(count(last.yield.kept, "fact"))."
        case .notFinished: "It has not finished a reading yet."
        case .unrecorded(let lastCall):
            "\(machine)'s last model call was on \(moments.dayAtTime(lastCall)), and it has no record of that reading."
        case .never: "\(machine) has not read yet."
        }
    }

    private static func next(_ due: Date, now: Date, _ moments: Moments) -> String {
        due <= now
            ? "Its next reading is due now." : "Its next reading is due on \(moments.dayAtTime(due))."
    }
}

/// Dates as the person reads them, in the zone passed in.
private struct Moments {
    let zone: TimeZone

    func dayAndTime(_ date: Date) -> String { "\(format(date, "d MMM")), \(format(date, "h:mm a"))" }
    func dayAtTime(_ date: Date) -> String { "\(format(date, "d MMM")) at \(format(date, "h:mm a"))" }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

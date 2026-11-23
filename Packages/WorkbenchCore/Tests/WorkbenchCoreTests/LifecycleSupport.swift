import Foundation
import GRDB
import Synchronization

@testable import WorkbenchCore

/// A time field of a reply, as the model writes it: the closed record and the words of the line that state it.
enum TimeJSON {
    static let none = record("unclear", precision: "none", words: "")

    static func record(
        _ direction: String, offset: Int = 0, weekday: String = "none", week: String = "none",
        part: String = "none", precision: String, ambiguous: Bool = false, words: String, minutes: Int = 0,
        dayOfMonth: Int = 0, month: Int = 0, monthWhich: String = "none", year: Int = 0, hour: Int = -1,
        minute: Int = 0, meridiem: String = "none"
    ) -> String {
        #"{"direction":"\#(direction)","precision":"\#(precision)","offset_days":\#(offset),"offset_minutes":\#(minutes),"weekday":"\#(weekday)","week":"\#(week)","day_of_month":\#(dayOfMonth),"month":\#(month),"month_which":"\#(monthWhich)","year":\#(year),"part_of_day":"\#(part)","clock_hour":\#(hour),"clock_minute":\#(minute),"meridiem":"\#(meridiem)","ambiguous":\#(ambiguous),"words":"\#(words)"}"#
    }

    /// A promise `offset` days after the day of the line, due at the end of that day.
    static func inDays(_ offset: Int, words: String) -> String {
        record("future", offset: offset, precision: "day", words: words)
    }
}

/// A reply item of the built-in fact machine, as the model writes it, with the relation it gave.
func pipItem(
    _ kind: String = "commitment", _ text: String = "Send the deck", person: String = "Asha",
    when: String = TimeJSON.none, cite: Int, quote: String, relation: String = "new", handle: String = "",
    outcome: String = ""
) -> String {
    #"{"kind":"\#(kind)","text":"\#(text)","person":"\#(person)","project":"Deck","when":\#(when),"asks":"team","stance":"said","relation":{"kind":"\#(relation)","handle":"\#(handle)","outcome":"\#(outcome)"},"cite":\#(cite),"quote":"\#(quote)"}"#
}

func pipReply(_ items: [String]) -> String { #"{"items":[\#(items.joined(separator: ","))]}"# }

/// A clock a test moves.
final class LifecycleClock: Sendable {
    private let now: Mutex<Date>

    init(_ start: Date = t0) { now = Mutex(start) }

    func set(_ date: Date) { now.withLock { $0 = date } }

    var read: @Sendable () -> Date { { [self] in now.withLock { $0 } } }
}

/// Work days for the lifecycle tests: the day of `t0` and the days after it.
enum Days {
    static let first = WorkDay(containing: t0)
    static let second = first.adding(days: 1)

    static func at(_ day: WorkDay, _ minutes: Double) -> Date { day.start.addingTimeInterval(minutes * 60) }
}

/// A store, a clock and the helpers to read a day with the fact machine and save what comes of it.
struct LifecycleWorld {
    let store: Store
    let clock: LifecycleClock
    static let members = ["members": ["Asha", "Raj"]]

    init() throws {
        clock = LifecycleClock()
        store = try makeStore(clock: clock.read)
    }

    var task: String { HelperSpec.team.task }
    var lifecycle: HelperSpec.Lifecycle { HelperSpec.team.lifecycle! }

    func line(_ id: Int64, _ day: WorkDay, _ minutes: Double, _ text: String) -> Evidence {
        Evidence(id: id, start: Days.at(day, minutes), line: "Asha: \(text)", quotable: [text])
    }

    /// Reads `lines` of `day` as the fact machine, with the model giving `items`, and saves the reading.
    @discardableResult
    func read(
        _ items: [String], lines: [Evidence], day: WorkDay = Days.first, asOf: WorkDay? = nil, readUpTo: Int64 = 0
    ) async throws -> HelperReader.Result {
        let open = try store.queries.openItems(readBy: .team, asOf: asOf)
        let evidence = EvidenceSet(lines: lines, context: Self.members, readUpTo: readUpTo)
        let reader = HelperReader(spec: .team, model: RecordedModel(ScriptedModel(pipReply(items)), store: store))
        let result = try await reader.read(day: day, scope: "work", evidence: evidence, open: open)
        try store.saveReading(
            result, of: .team, day: day, scope: "work", grant: grant(.whatsapp, label: "work", at: clock.read()))
        return result
    }

    /// A read of the store from a function that is not async, so a test can read inside an async body.
    func db<T>(_ body: (Database) throws -> T) throws -> T { try store.writer.read(body) }

    func commit<T>(_ body: (Database) throws -> T) throws -> T { try store.writer.write(body) }

    func open() throws -> [Item] { try store.queries.openItems(of: task, lifecycle: lifecycle) }

    func all() throws -> [Item] { try store.queries.items(of: task, since: Days.first.adding(days: -1)) }

    func kinds(of item: Int64) throws -> [String] {
        try db {
            try String.fetchAll($0, sql: "SELECT kind FROM item_event WHERE item_id = ? ORDER BY id", arguments: [item])
        }
    }
}

import Foundation

@testable import WorkbenchCore

/// Shows that a member field names a member, not a display string: the one roster lookup, the Verifier through it, the
/// grouping of old and new stored values, and a time schema that cannot write a part of the day with a day. It uses
/// no model and no store.

var failures = 0

func check(_ name: String, _ ok: Bool) {
    print("  \(ok ? "ok  " : "FAIL") \(name)")
    if !ok { failures += 1 }
}

let founder = "Meera Rao"
let roster = MemberRoster(names: ["Aditi Verma", founder], founder: founder)

print("1. The roster lookup (one place; every reader of a member value uses it)")
for value in ["Meera Rao", "Meera Rao (You)", "Aditi Verma", "Priya Nair", "Aditi Verma (You)"] {
    print("  \"\(value)\" -> \(roster.member(for: value).map { "member \"\($0)\"" } ?? "no member")")
}
check("the plain name and the older label are the same member", roster.member(for: "Meera Rao (You)") == founder)
check("an unknown name is no member", roster.member(for: "Priya Nair") == nil)
check("only the founder has an older label", roster.member(for: "Aditi Verma (You)") == nil)

print("\n2. The Verifier, through the lookup (Pip's spec, chat lines show the founder by plain name)")
let calendar = Calendar.gregorian(in: TimeZone(identifier: "Asia/Kolkata")!)
let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))!
let line = Evidence(
    id: 1, start: start, line: "Meera Rao: Aditi, send the deck today.", quotable: ["Aditi, send the deck today."])
let window = EvidenceSet(
    lines: [line], context: ["members": ["Aditi Verma", founder], MemberRoster.founderEntry: [founder]])
let day = WorkDay(containing: start, calendar: calendar)

func proposal(person: String, when: String = noTime) throws -> [String: JSONValue] {
    let text = """
        {"person":"\(person)","project":"General","kind":"plan","text":"Send the deck.","when":\(when),
        "stance":"said","asks":"team","cite":1,"quote":"send the deck today",
        "relation":{"kind":"new","handle":"","outcome":""}}
        """
    return try JSONDecoder().decode([String: JSONValue].self, from: Data(text.utf8))
}

let noTime = """
    {"direction":"unclear","precision":"none","offset_days":0,"offset_minutes":0,"weekday":"none","week":"none",\
    "day_of_month":0,"month":0,"month_which":"none","year":0,"part_of_day":"none","clock_hour":-1,"clock_minute":0,\
    "meridiem":"none","ambiguous":false,"words":""}
    """

func verdict(_ person: String) throws -> String {
    let verifier = Verifier(window: window, zone: calendar.timeZone)
    switch verifier.verdict({
        try verifier.item(
            proposal(person: person), spec: .team, open: [], day: day, scope: "demo", run: 1)
    }) {
    case .accepted(let item): return "kept, stored as \"\(item["person"])\""
    case .dropped(let rule): return "dropped (\(rule.rawValue))"
    }
}

for person in ["Meera Rao", "Meera Rao (You)", "Priya Nair"] {
    print("  person \"\(person)\": \(try verdict(person))")
}
check("the founder's plain name is kept", try verdict("Meera Rao") == "kept, stored as \"Meera Rao\"")
check("the older label is kept as the same member", try verdict("Meera Rao (You)") == "kept, stored as \"Meera Rao\"")
check("an unknown name is dropped", try verdict("Priya Nair") == "dropped (field_kind)")

print("\n3. Grouping over old and new stored values (rows are not rewritten)")
func fact(_ person: String, _ id: Int64) -> Item {
    Item(
        id: id, task: HelperSpec.team.task, day: day, scope: "demo", source: .whatsapp, citeFirst: id, citeLast: id,
        start: start, end: start, fields: ["person": person, "kind": "plan"], quote: "q\(id)", run: nil)
}
let stored = [fact("Meera Rao (You)", 1), fact("Meera Rao", 2), fact("Aditi Verma", 3), fact("Meera Rao (You)", 4)]
let lifecycle = HelperSpec.team.lifecycle
let now = start.addingTimeInterval(3600)
let byRawValue = FactGroups.make(stored, by: { _ in "person" }, lifecycle: { _ in lifecycle }, now: now)
let byMember = FactGroups.make(stored, by: { _ in "person" }, roster: roster, lifecycle: { _ in lifecycle }, now: now)
print("  without the lookup: \(byRawValue.map { "\($0.name) x\($0.open.count + $0.rest.count)" })")
print("  with the lookup:    \(byMember.map { "\($0.name) x\($0.open.count + $0.rest.count)" })")
check("raw values split the founder in two", byRawValue.count == 3)
check(
    "the lookup groups the founder once, with all 3 facts",
    byMember.count == 2 && byMember.first { $0.name == founder }.map { $0.open.count + $0.rest.count } == 3)
check("the stored rows still hold the old label", stored[0]["person"] == "Meera Rao (You)")

var morning = MorningInput(facts: stored, me: founder)
morning.ownerField = { _ in "person" }
let sections = MorningList.pick(morning, now: now)
let owed = sections.first { $0.kind == .owe }?.needs.count ?? 0
print("  Morning list, what the founder owes: \(owed) of 3 founder facts (old and new values)")
check("the morning list counts old and new values as the founder's", owed == 3)

let shown = HelperSpec.team.resolvingMembers(of: stored[0], in: window.context)
check("a board or page shows the plain name for an old value", shown["person"] == founder)

print("\n4. The time schema refuses a part of the day with a day")
func reply(precision: String, partOfDay: String) -> String {
    noTime.replacingOccurrences(of: "\"precision\":\"none\"", with: "\"precision\":\"\(precision)\"")
        .replacingOccurrences(of: "\"part_of_day\":\"none\"", with: "\"part_of_day\":\"\(partOfDay)\"")
}
let schema = TimeMention.schema
if case .anyOf(let shapes) = schema { print("  \(shapes.count) shapes, by the parts of the day a precision may carry") }
for (precision, part) in [
    ("day", "evening"), ("day", "none"), ("part_of_day", "evening"), ("part_of_day", "none"), ("hour", "evening"),
    ("week", "morning"),
] {
    print(
        "  precision \(precision), part_of_day \(part): \(schema.accepts(json: reply(precision: precision, partOfDay: part)) ? "can be written" : "refused by the schema")"
    )
}
check("day with evening is refused", !schema.accepts(json: reply(precision: "day", partOfDay: "evening")))
check("day with none is accepted", schema.accepts(json: reply(precision: "day", partOfDay: "none")))
check(
    "part_of_day with evening is accepted", schema.accepts(json: reply(precision: "part_of_day", partOfDay: "evening")))
check("part_of_day with none is refused", !schema.accepts(json: reply(precision: "part_of_day", partOfDay: "none")))
check("hour may carry a part of the day", schema.accepts(json: reply(precision: "hour", partOfDay: "evening")))
let text = try schema.jsonText
check(
    "the CLI form has anyOf and no oneOf or if",
    text.hasPrefix("{\"anyOf\"") && !text.contains("oneOf") && !text.contains("\"if\""))

print(failures == 0 ? "\nall checks pass" : "\n\(failures) checks FAIL")
exit(failures == 0 ? 0 : 1)

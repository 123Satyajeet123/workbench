import Foundation
import Synchronization
import WorkbenchCore

// Shows each rule of the `objectRef` field kind twice: once where code keeps the object, once where it drops it.
// A scripted model and one scratch store, synthetic words only, no network.

nonisolated final class ScriptedModel: StructuredModel, Sendable {
    let name = "scripted"
    let reply: String
    let inputs: Mutex<[String]>

    init(_ reply: String) {
        self.reply = reply
        inputs = Mutex([])
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        inputs.withLock { $0.append(input) }
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name, usage: Usage(), reply: reply)
    }
}

var failures = 0

func expect(_ claim: String, _ holds: Bool) {
    print("  \(holds ? "yes" : "NO ") \(claim)")
    if !holds { failures += 1 }
}

let now = Date(timeIntervalSince1970: 1_795_000_000)
let day = WorkDay(containing: now)
let store = try Store(
    directory: FileManager.default.temporaryDirectory.appending(path: "objectref-demo-\(UUID().uuidString)"),
    clock: { now })
let grant = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: ["team"]])
    .authorize(CaptureRequest(kind: .whatsapp, label: "team"), at: now).grant!

let acme = try store.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Acme")
let bolt = try store.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Bolt")
let old = try store.createWorkObject(type: ObjectTypes.deal, parent: nil, name: "Old Co")
let login = try store.createWorkObject(type: ObjectTypes.project, parent: nil, name: "Login")
try store.archive(old.id)

var spec = HelperSpec.team
spec.fields.append(.init("deal", .objectRef(type: ObjectTypes.deal.id), meaning: "The deal the fact is about."))

let evidence = EvidenceSet(
    lines: [
        Evidence(
            id: 11, start: now, line: "Asha: Acme wants the deck", quotable: ["Acme wants the deck"])
    ], context: ["members": ["Asha"]])

func reply(deal: String, object: String = "") -> String {
    let when =
        #"{"direction":"unclear","offset_days":0,"weekday":"none","week":"none","part_of_day":"none","offset_minutes":0,"day_of_month":0,"month":0,"month_which":"none","year":0,"clock_hour":-1,"clock_minute":0,"meridiem":"none","precision":"none","ambiguous":false,"words":""}"#
    return
        #"{"items":[{"person":"Asha","project":"Login","kind":"done","text":"Deck","when":\#(when),"asks":"team","stance":"said","deal":"\#(deal)","relation":{"kind":"new","handle":"","outcome":""},"object":"\#(object)","cite":11,"quote":"Acme wants the deck"}]}"#
}

func read(_ scripted: String) async throws -> (HelperReader.Result, ScriptedModel) {
    let model = ScriptedModel(scripted)
    let objects = try store.queries.objectsToShow(for: spec)
    let reader = HelperReader(spec: spec, model: RecordedModel(model, store: store), objects: objects)
    return (try await reader.read(day: day, scope: "team", evidence: evidence), model)
}

func handle(of object: WorkObject) throws -> String {
    let shown = try store.queries.objectsToShow(for: spec)
    guard let index = shown.firstIndex(where: { $0.id == object.id }) else { return "none" }
    return "O\(index + 1)"
}

print("What the model is shown")
let (kept, model) = try await read(reply(deal: try handle(of: acme)))
let shown = model.inputs.withLock { $0[0] }
print(shown.split(separator: "\n").prefix(12).map { "    " + $0 }.joined(separator: "\n"))
expect("a live deal is listed under the field", shown.contains("Objects for deal:\nO") && shown.contains("Acme"))
expect("an archived deal is not listed", !shown.contains("Old Co"))
let dealList = shown.components(separatedBy: "Objects for deal:")[1].components(separatedBy: "Work day")[0]
expect("a project is a place to file, but is not in the list for the deal field", !dealList.contains("Login"))

print("\nThe model names a deal it was shown")
expect("the fact is kept, and nothing is dropped", kept.items.count == 1 && kept.dropped == 0)
expect("the field holds the object's id, not its name", kept.items.first?["deal"] == acme.id)
try store.saveReading(kept, of: spec, day: day, scope: "team", grant: grant)
let stored = try store.queries.items(of: spec.task, day: day, scope: "team")
let name = try stored.first.flatMap { try store.queries.workObject($0["deal"]) }?.name
expect("the name comes from the object: \(name ?? "none")", name == "Acme")

print("\nThe model names something code did not give it")
let refused: [(String, String)] = [
    ("an id that was never shown", "O99"),
    ("a name in place of a handle", "Acme"),
    ("the real id in place of a handle", acme.id),
    ("the handle of an object of another type (a project)", try handle(of: login)),
]
for (what, given) in refused {
    let (result, _) = try await read(reply(deal: given))
    let rules = try result.run.map { try store.queries.dropReasons(of: $0).map(\.rule) } ?? []
    expect("\(what): the fact is dropped as unknown_handle", result.items.isEmpty && rules == [.unknownHandle])
}

print("\nAn empty handle")
let (empty, _) = try await read(reply(deal: ""))
expect("means no object: the fact is kept with an empty field", empty.items.first?["deal"] == "" && empty.dropped == 0)

print("\nThe home of a fact uses the same handles")
let (homed, _) = try await read(reply(deal: "", object: try handle(of: bolt)))
expect("a place that was shown becomes a proposed home", homed.homes.map(\.object) == [bolt.id])
let (misplaced, _) = try await read(reply(deal: "", object: "O99"))
let homeRules = try misplaced.run.map { try store.queries.dropReasons(of: $0).map(\.rule) } ?? []
expect(
    "a place that was not shown is recorded as unknown_handle, and the fact stays",
    misplaced.items.count == 1 && misplaced.homes.isEmpty && homeRules == [.unknownHandle])

print("\nFacts that code makes from a deal read the same field")
try store.setRevisit(of: acme, on: day.adding(days: 30), reason: "no revenue")
expect("the revisit of Acme is found by its deal", try store.queries.revisits(of: acme.id).count == 1)
expect("the revisit is not found for another deal", try store.queries.revisits(of: bolt.id).isEmpty)
expect(
    "the revisit is filed under the deal it was made from",
    try store.queries.home(of: try need(store.queries.revisits(of: acme.id).first?.id))?.id == acme.id)

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)

struct Missing: Error {}

func need<T>(_ value: T?) throws -> T {
    guard let value else { throw Missing() }
    return value
}

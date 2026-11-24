import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct AuditPolicyTests {
    private let day = WorkDay(containing: t0)

    private func reading(items count: Int, in store: Store, isAudited: ((Int) -> Bool)? = nil) async throws {
        let model = RecordedModel(ScriptedModel(#"{"items":[]}"#), store: store)
        let (_, run) = try await model.generate(
            HelperReader.Reply.self, schema: .object([.init("items", .array(.string))]), task: "day.timeline",
            instructions: "v1", input: "x", holding: [])
        let items = (0..<count).map { index in
            Item(
                task: "day.timeline", day: day, scope: "", source: .screen, citeFirst: Int64(index),
                citeLast: Int64(index), start: day.start.addingTimeInterval(Double(index) * 600),
                end: day.start.addingTimeInterval(Double(index) * 600 + 300), fields: ["task": "t\(index)"],
                quote: "q", run: run)
        }
        let result = HelperReader.Result(items: items, dropped: 0, run: run)
        if let isAudited {
            try store.saveReading(
                result, of: .timeline, day: day, scope: "", grant: grant(.screen), isAudited: isAudited)
        } else {
            try store.saveReading(result, of: .timeline, day: day, scope: "", grant: grant(.screen))
        }
    }

    private func askedWith(_ store: Store) throws -> [Double?] {
        try store.queries.items(of: "day.timeline", day: day, scope: "").map(\.askedWith)
    }

    @Test func everyAuditedItemIsLoggedWithTheSameChanceWhateverTheSizeOfItsReading() async throws {
        let store = try makeStore()
        try await reading(items: 300, in: store)
        let chances = try askedWith(store)
        let picked = chances.compactMap { $0 }
        #expect(picked.allSatisfy { $0 == RunSettings.standard.pickChance })
        #expect((20...75).contains(picked.count), "about 15 of 100 items are picked: \(picked.count) of 300")
    }

    @Test func eachItemIsPickedOnItsOwnSoAReadingMayHaveSeveralOrNoAudits() async throws {
        let several = try makeStore()
        try await reading(items: 5, in: several, isAudited: { $0 != 2 })
        #expect(try askedWith(several).compactMap { $0 }.count == 4)
        let none = try makeStore()
        try await reading(items: 5, in: none, isAudited: { _ in false })
        #expect(try askedWith(none).compactMap { $0 }.isEmpty)
    }
}

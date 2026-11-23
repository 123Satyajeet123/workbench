import Foundation
import Testing

@testable import WorkbenchCore

private let screenOn = CapturePolicy(switches: [.screen: true, .screenText: true])

/// The capture log's Delete passes a window row to `Store.delete`. The screen text read from that window goes with it.
struct WindowDeleteTests {
    private func word() -> String { "zxq\(UInt32.random(in: 100_000...999_999))text" }

    private func window(_ id: Int, app: String, text: String) -> ScreenSnapshot {
        ScreenSnapshot(app: app, bundleID: "com.example.\(app)", windowID: id, title: "w\(id)", text: text)
    }

    private func record(
        _ engine: inout CaptureEngine, _ snapshot: ScreenSnapshot, presence: PresenceState = .active,
        at time: Date, into store: Store
    ) throws {
        let batch = engine.observe(snapshot, presence: presence, policy: screenOn, at: time)
        try store.record(#require(batch))
    }

    private func copies(of word: String, in store: Store) throws -> Int {
        try ["workbench.sqlite", "workbench.sqlite-wal"].reduce(0) {
            let bytes = try Data(contentsOf: store.directory.appending(path: $1))
            return $0 + (bytes.range(of: Data(word.utf8)) == nil ? 0 : 1)
        }
    }

    private func windowRow(titled title: String, in store: Store) throws -> Activity {
        try #require(store.queries.activities(since: .distantPast).first { $0.kind == .window && $0.title == title })
    }

    @Test func deletingAWindowRemovesItsTextEvenAfterTheTextWasReadAgainAndLeavesOtherWindows() throws {
        let store = try makeStore()
        var engine = CaptureEngine()
        let (first, again, other) = (word(), word(), word())
        try record(&engine, window(1, app: "Notes", text: first), at: t0, into: store)
        try record(&engine, window(1, app: "Notes", text: again), at: t0 + 61, into: store)
        try record(&engine, window(2, app: "Mail", text: other), at: t0 + 130, into: store)
        for planted in [first, again, other] { #expect(try copies(of: planted, in: store) > 0) }

        try store.delete(.activities(ActivityFilter(id: try windowRow(titled: "w1", in: store).id)))

        #expect(try copies(of: first, in: store) == 0)
        #expect(try copies(of: again, in: store) == 0)
        #expect(try copies(of: other, in: store) > 0)
        let kept = try store.queries.activities(since: .distantPast)
        #expect(kept.filter { $0.kind == .text }.compactMap(\.text) == [other])
        #expect(kept.contains { $0.kind == .window && $0.title == "w2" })
    }

    @Test func aLaterStretchInTheSameAppKeepsItsText() throws {
        let store = try makeStore()
        var engine = CaptureEngine()
        let (early, later) = (word(), word())
        try record(&engine, window(1, app: "Notes", text: early), at: t0, into: store)
        try record(&engine, window(1, app: "Notes", text: "x"), presence: .idle, at: t0 + 300, into: store)
        try record(&engine, window(3, app: "Notes", text: later), at: t0 + 600, into: store)

        try store.delete(.activities(ActivityFilter(id: try windowRow(titled: "w1", in: store).id)))

        #expect(try copies(of: early, in: store) == 0)
        #expect(try copies(of: later, in: store) > 0)
    }
}

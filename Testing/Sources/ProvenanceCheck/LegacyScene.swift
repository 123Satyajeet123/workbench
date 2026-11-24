import Foundation
import GRDB
import Kernel
import Lines

@testable import WorkbenchCore

/// Two WhatsApp chats whose lines carry old citation ids (global row numbers: 100 and 101 in the first chat, 102 and 103
/// in the second), a run that has no window, and facts and events that cite those ids; and a typed fact that quotes a
/// line by its row. These are the shapes of the old erase that no window explains.
struct LegacyScene {
    static let chats = ["120363111111111111@g.us", "120363222222222222@g.us"]

    let store: Store
    let erased = canary("legacyerased")
    let kept = canary("legacykept")
    var windowedFact: Int64 = 0
    var firstFact: Int64 = 0
    var secondFact: Int64 = 0
    var typedFact: Int64 = 0
    var event: Int64 = 0

    func erasure(chat: Int) -> LineSelection {
        LineSelection(
            sql: "SELECT line_id FROM evidence WHERE container = ?", arguments: [Self.chats[chat]])
    }

    static func make(in directory: URL) throws -> LegacyScene {
        let store = try Store(directory: directory)
        try store.savePolicy(CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: Set(Self.chats)]))
        var scene = LegacyScene(store: store)
        try scene.write(owner: try PersonID("owner-1"))
        try scene.addFacts()
        return scene
    }

    private func write(owner: PersonID) throws {
        for (index, chat) in Self.chats.enumerated() {
            let lines = try (0..<2).map { offset in
                ObservedLine(
                    line: Line(
                        entity: try EntityKey.whatsAppGroup(
                            chat: chat, author: .member("91@s.whatsapp.net"), stanzaID: "s\(offset)"),
                        text: "legacy words \(index) \(offset) \(index == 0 ? (offset == 0 ? erased : "plain") : kept)",
                        readerVersion: "check 1"),
                    eventTime: UTCInstant(milliseconds: 1_795_000_000_000), actor: "91@s.whatsapp.net",
                    legacy: LegacyRef(space: .whatsAppRow, ref: Int64(100 + index * 2 + offset)))
            }
            let now = Date()
            let grant = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: Set(Self.chats)])
                .authorize(CaptureRequest(kind: .whatsapp, label: chat), at: now).grant!
            try store.record(
                SourceReading(
                    grant: grant, label: chat, container: chat,
                    audience: AudienceDigest(owner: "me", members: ["91@s.whatsapp.net"]), lines: lines,
                    cursorAfter: ScanCursor(storeID: "U1", lastRow: 1, readAt: now), mapsLegacyRefs: false,
                    readerVersion: "check 1"),
                of: .whatsAppChat, owner: owner)
        }
    }

    func revoke(stanza: String, chat: Int) throws {
        let now = Date()
        let grant = CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: Set(Self.chats)])
            .authorize(CaptureRequest(kind: .whatsapp, label: Self.chats[chat]), at: now).grant!
        try store.record(
            SourceReading(
                grant: grant, label: Self.chats[chat], container: Self.chats[chat],
                audience: AudienceDigest(owner: "me", members: ["91@s.whatsapp.net"]),
                lines: [
                    ObservedLine(
                        line: .tombstone(
                            entity: try EntityKey.whatsAppGroup(
                                chat: Self.chats[chat], author: .member("91@s.whatsapp.net"), stanzaID: stanza),
                            readerVersion: "check 1"),
                        eventTime: UTCInstant(milliseconds: 1_795_000_000_000), actor: "91@s.whatsapp.net",
                        legacy: nil)
                ], cursorAfter: ScanCursor(storeID: "U1", lastRow: 2, readAt: now), mapsLegacyRefs: false,
                readerVersion: "check 1"),
            of: .whatsAppChat, owner: try PersonID("owner-1"))
    }

    private mutating func addFacts() throws {
        let run = try store.beginRun(task: "legacy", model: "synthetic", prompt: "none", input: "x", kinds: [.whatsapp])
        let now = Date()
        let day = WorkDay(containing: now)
        func fact(
            _ scope: String, _ word: String, source: SourceKind = .whatsapp, run: RunID? = run, quoteLine: Int64? = nil
        ) -> Item {
            Item(
                task: "legacy", day: day, scope: scope, source: source, citeFirst: 100, citeLast: 103, start: now,
                end: now, fields: ["text": "words \(word)"], quote: "quote \(word)", run: run,
                quoteSpan: quoteLine.map { QuoteSpan(line: $0, part: 0, start: 0, end: 5) })
        }
        let lines = try store.rows(
            "SELECT line_id FROM evidence WHERE container = ? ORDER BY id", [Self.chats[0]]
        ).map { $0["line_id"] as Data }
        let windowRun = try store.beginRun(
            task: "legacy", model: "synthetic", prompt: "none", input: "legacy words \(erased)", kinds: [.whatsapp],
            window: lines.enumerated().map { WindowLine(number: Int64($0.offset + 1), lineID: $0.element) })
        let windowed = Item(
            task: "legacy", day: day, scope: Self.chats[0], source: .whatsapp, citeFirst: 1, citeLast: 1, start: now,
            end: now, fields: ["text": "words \(erased)"], quote: "legacy words \(erased)", run: windowRun,
            quoteSpan: QuoteSpan(line: 1, part: 0, start: 0, end: 12))
        let firstLineRow = try store.count(
            "SELECT id FROM evidence WHERE container = ? ORDER BY id LIMIT 1", [Self.chats[0]])
        try store.writer.write { db in
            firstFact = try Store.insertItem(db, fact(Self.chats[0], erased), at: now)
            windowedFact = try Store.insertItem(db, windowed, at: now)
            secondFact = try Store.insertItem(db, fact(Self.chats[1], kept), at: now)
            typedFact = try Store.insertItem(
                db, fact("", erased, source: .typed, run: nil, quoteLine: Int64(firstLineRow)), at: now)
        }
        try store.writer.write { db in
            try store.addEvent(db, item: firstFact, kind: .restate, at: now, by: (run, 100, "legacy quote"))
        }
        event = Int64(try store.count("SELECT MAX(id) FROM item_event"))
    }
}

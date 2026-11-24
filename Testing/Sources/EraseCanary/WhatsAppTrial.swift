import Foundation
import GRDB
import LocalSources

@testable import WorkbenchCore

/// What the reader and the store do with the shapes an edit and a delete for everyone could take in WhatsApp's store.
/// Nothing public says which shape the real store uses, so each one is tried on an invented store.
enum WhatsAppTrial {
    enum Shape: String, CaseIterable {
        case editInPlace = "text edited in place, same row and stanza id"
        case editNewRowOldKept = "edit as a new row with the same stanza id, old row kept"
        case editNewRowOldGone = "edit as a new row with the same stanza id, old row deleted"
        case revokeBlanksText = "revoke blanks the text, type stays text"
        case revokeSetsType = "revoke sets type 14 and blanks the text"
        case revokeSetsTypeKeepsText = "revoke sets type 14 and leaves the text"
        case rowDisappears = "the row disappears"
        case editOfOldMessage = "edit of a message older than the edit window"
        case revokeOfOldMessage = "revoke (type 14) of a message older than the edit window"

        var isOld: Bool { self == .editOfOldMessage || self == .revokeOfOldMessage }

        func apply(to storage: SyntheticChatStorage, edited: String) throws {
            let text = "Asha Example: please send \(edited) to Ravi Example by Monday"
            switch self {
            case .editInPlace, .editOfOldMessage:
                try storage.change {
                    try $0.execute(sql: "UPDATE ZWAMESSAGE SET ZTEXT = ? WHERE Z_PK = 1001", arguments: [text])
                }
            case .editNewRowOldKept: try storage.insert(row: 1003, stanza: "A1", text: text)
            case .editNewRowOldGone:
                try storage.change { try $0.execute(sql: "DELETE FROM ZWAMESSAGE WHERE Z_PK = 1001") }
                try storage.insert(row: 1003, stanza: "A1", text: text)
            case .revokeBlanksText:
                try storage.change { try $0.execute(sql: "UPDATE ZWAMESSAGE SET ZTEXT = NULL WHERE Z_PK = 1001") }
            case .revokeSetsType, .revokeOfOldMessage:
                try storage.change {
                    try $0.execute(sql: "UPDATE ZWAMESSAGE SET ZMESSAGETYPE = 14, ZTEXT = NULL WHERE Z_PK = 1001")
                }
            case .revokeSetsTypeKeepsText:
                try storage.change { try $0.execute(sql: "UPDATE ZWAMESSAGE SET ZMESSAGETYPE = 14 WHERE Z_PK = 1001") }
            case .rowDisappears:
                try storage.change { try $0.execute(sql: "DELETE FROM ZWAMESSAGE WHERE Z_PK = 1001") }
            }
        }
    }

    static func run(in root: URL, findings: Findings) async throws {
        print("\n== WhatsApp edit and delete-for-everyone trial, on an invented ChatStorage.sqlite")
        for shape in Shape.allCases { try await trial(shape, in: root.appending(path: "\(shape)"), findings: findings) }
    }

    private static func trial(_ shape: Shape, in folder: URL, findings: Findings) async throws {
        let scene = try Scene(in: folder.appending(path: "store"), words: Words())
        try await scene.build()
        let storage = try SyntheticChatStorage(in: folder.appending(path: "container"))
        let age = shape.isOld ? 10.0 : 0
        try storage.insert(
            row: 1001, stanza: "A1", text: "Asha Example: please send \(scene.words.canary) to Ravi Example by Friday",
            daysOld: age)
        try storage.insert(
            row: 1002, stanza: "A2", text: "Ravi Example: the invoice \(scene.words.sameChat) is paid", daysOld: age)
        let reader = WhatsAppChatReader(container: storage.container, chatJID: Scene.chatA, policy: scene.store)
        let edited = Words.random()
        let first = try await scene.store.ingest(reader, owner: scene.owner, now: Date())
        findings.expect(
            first.inserted == 0 && first.seenAgain == 2 && first.failures.isEmpty,
            "\(shape.rawValue): the reader gives the same lines the writer stored (\(describe(first)))")
        try shape.apply(to: storage, edited: edited)
        let second = try await scene.store.ingest(reader, owner: scene.owner, now: Date().addingTimeInterval(3600))
        let third = try await scene.store.ingest(reader, owner: scene.owner, now: Date().addingTimeInterval(7200))
        try print(report(shape, scene: scene, edited: edited, reads: [second, third]))
        try scene.store.writer.close()
    }

    private static func describe(_ report: IngestReport) -> String {
        "inserted \(report.inserted), seen again \(report.seenAgain), tombstones \(report.tombstones), erased \(report.erasedLines), flagged facts \(report.flaggedItems), failures \(report.failures.count)"
    }

    private static func report(_ shape: Shape, scene: Scene, edited: String, reads: [IngestReport]) throws -> String {
        let lines = try scene.store.rows(
            "SELECT tombstone, text FROM evidence WHERE container = ? AND message_ref = 'A1' ORDER BY id", [Scene.chatA]
        ).map { row -> String in
            let text: String = row["text"]
            let kind = (row["tombstone"] as Int) == 1 ? "tombstone" : "text"
            return text.contains(scene.words.canary)
                ? "\(kind) with the old words"
                : text.contains(edited) ? "\(kind) with the new words" : "\(kind) (no words)"
        }
        let fact = try scene.store.rows("SELECT source_deleted, quote FROM item ORDER BY id LIMIT 1").first
        let factText =
            fact.map {
                ($0["source_deleted"] as Int) == 1
                    ? "flagged, quote emptied" : "quote kept: \($0["quote"] as String)".prefix(60).description
            } ?? "no fact"
        let oldWordFiles = Set(ByteScan.hits(of: scene.words.canary, under: scene.directory).map(\.file)).sorted()
        return """
            TRIAL: \(shape.rawValue)
                read 2: \(describe(reads[0]))
                read 3: \(describe(reads[1]))
                lines of the message: \(lines)
                fact that quoted it: \(factText)
                old words still in: \(oldWordFiles.isEmpty ? "no file" : oldWordFiles.joined(separator: ", "))
            """
    }
}

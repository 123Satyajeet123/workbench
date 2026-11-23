import CaptureService
import Foundation
import SQLite3
import Synchronization
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@Suite struct VoiceNoteTests {
    private let noon: Date = {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))!
    }()

    @Test func aWhatsAppVoiceNoteBecomesALineOfWhatWasSaid() async throws {
        let container = try whatsApp(at: noon)
        let media = container.appending(path: "Message/Media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data("opus".utf8).write(to: media.appending(path: "note.opus"))
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let seconds = noon.timeIntervalSinceReferenceDate + 120
        let sql = """
            INSERT INTO ZWAMESSAGE VALUES (20, 1, \(seconds), 3, NULL, 0, 2);
            INSERT INTO ZWAMEDIAITEM (ZMESSAGE, ZMEDIALOCALPATH, ZTITLE) VALUES (20, 'Media/note.opus', NULL);
            """
        #expect(sqlite3_open(container.appending(path: "ChatStorage.sqlite").path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)

        let store = try scratchStore(clock: { [noon] in noon })
        let heard = Mutex<[URL]>([])
        let source = try WhatsAppSource(
            store: store, capture: try CaptureService(store: store), task: HelperSpec.team.task, founder: { "Kabir" },
            container: container,
            hear: { urls in
                heard.withLock { $0 += urls }
                return Dictionary(uniqueKeysWithValues: urls.map { ($0, "payments are blocked on the keys") })
            })
        try source.loadGroups()
        try source.choose(try #require(source.groups.first))
        let lines = try await source.evidence(on: WorkDay(containing: noon)).lines
        #expect(lines.last?.line == "Bharat: [voice note] payments are blocked on the keys")
        #expect(heard.withLock { $0 }.map(\.lastPathComponent) == ["note.opus"], "only the voice note is listened to")
    }
}

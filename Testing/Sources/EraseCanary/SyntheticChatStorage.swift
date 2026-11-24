import Foundation
import GRDB

/// An invented `ChatStorage.sqlite` in the layout the reader reads (the columns of `WhatsAppFixture` in the tests of
/// BaseKit): one group chat with one member. It holds no real data. Each change opens the file, changes it and closes it.
struct SyntheticChatStorage {
    static let group = Scene.chatA
    static let session = 4
    static let member = 1

    let container: URL
    private var file: URL { container.appending(path: "ChatStorage.sqlite") }

    init(in container: URL) throws {
        self.container = container
        try FileManager.default.createDirectory(
            at: container.appending(path: "Message/Media"), withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: file.path)
        try queue.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode = WAL") }
        try queue.close()
        try change { db in
            try db.execute(
                sql: """
                    CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZSESSIONTYPE INTEGER,
                        ZPARTNERNAME TEXT, ZLASTMESSAGEDATE REAL);
                    CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMESSAGEDATE REAL,
                        ZMESSAGETYPE INTEGER, ZTEXT TEXT, ZISFROMME INTEGER, ZGROUPMEMBER INTEGER, ZSTANZAID TEXT,
                        ZFLAGS INTEGER);
                    CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMESSAGE INTEGER, ZMEDIALOCALPATH TEXT,
                        ZTITLE TEXT, ZMETADATA BLOB);
                    CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID TEXT);
                    INSERT INTO Z_METADATA VALUES (1, 'STORE-UUID-SYNTHETIC');
                    CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMEMBERJID TEXT,
                        ZCONTACTNAME TEXT, ZFIRSTNAME TEXT, ZISACTIVE INTEGER);
                    CREATE TABLE ZWAPROFILEPUSHNAME (Z_PK INTEGER PRIMARY KEY, ZJID TEXT, ZPUSHNAME TEXT);
                    INSERT INTO ZWACHATSESSION VALUES (\(Self.session), '\(Self.group)', 1, 'Team Example', 50);
                    INSERT INTO ZWAGROUPMEMBER VALUES (\(Self.member), \(Self.session), 'a@s.whatsapp.net', 'Asha Example', NULL, 1);
                    """)
        }
    }

    func change(_ body: (Database) throws -> Void) throws {
        let queue = try DatabaseQueue(path: file.path)
        try queue.write(body)
        try queue.close()
    }

    func insert(row: Int, stanza: String, text: String?, type: Int = 0, daysOld: Double = 0) throws {
        let date = Date().addingTimeInterval(-daysOld * 86_400).timeIntervalSinceReferenceDate
        try change { db in
            try db.execute(
                sql: """
                    INSERT INTO ZWAMESSAGE(Z_PK, ZCHATSESSION, ZMESSAGEDATE, ZMESSAGETYPE, ZTEXT, ZISFROMME, ZGROUPMEMBER,
                        ZSTANZAID, ZFLAGS) VALUES (?, ?, ?, ?, ?, 0, ?, ?, 0)
                    """, arguments: [row, Self.session, date, type, text, Self.member, stanza])
        }
    }
}

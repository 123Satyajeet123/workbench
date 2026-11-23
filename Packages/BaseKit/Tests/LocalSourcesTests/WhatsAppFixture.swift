import Foundation
import SQLite3
import WorkbenchCore

let selfJID = "919800000001@s.whatsapp.net"
let otherJID = "919800000002@s.whatsapp.net"
let groupJID = "120300000000000001@g.us"
let otherGroupJID = "120300000000000002@g.us"

struct FixedPolicy: CapturePolicyProvider {
    var policy: CapturePolicy
    func currentPolicy() async throws -> CapturePolicy { policy }
}

let whatsappOn = FixedPolicy(
    policy: CapturePolicy(switches: [.whatsapp: true], allowList: [.whatsapp: [selfJID, groupJID]]))

/// A container folder with a `ChatStorage.sqlite` that has the columns the reader uses. Chats: 1 the founder's own,
/// 2 a friend, 3 the founder's status feed (same ID), 4 the team group, 5 another group.
struct WhatsAppFixture {
    let container: URL

    init() throws {
        container = FileManager.default.temporaryDirectory.appending(path: "wa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: container.appending(path: "Message/Media"), withIntermediateDirectories: true)
        try run(
            """
            PRAGMA journal_mode = WAL;
            CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZSESSIONTYPE INTEGER,
                ZPARTNERNAME TEXT, ZLASTMESSAGEDATE REAL);
            CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMESSAGEDATE REAL,
                ZMESSAGETYPE INTEGER, ZTEXT TEXT, ZISFROMME INTEGER, ZGROUPMEMBER INTEGER, ZSTANZAID TEXT, ZFLAGS INTEGER);
            CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMESSAGE INTEGER, ZMEDIALOCALPATH TEXT, ZTITLE TEXT,
                ZMETADATA BLOB);
            CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID TEXT);
            INSERT INTO Z_METADATA VALUES (1, 'STORE-UUID-1');
            CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMEMBERJID TEXT,
                ZCONTACTNAME TEXT, ZFIRSTNAME TEXT, ZISACTIVE INTEGER);
            CREATE TABLE ZWAPROFILEPUSHNAME (Z_PK INTEGER PRIMARY KEY, ZJID TEXT, ZPUSHNAME TEXT);
            INSERT INTO ZWACHATSESSION VALUES (1, '\(selfJID)', 0, 'Me', 10), (2, '\(otherJID)', 0, 'Friend', 20),
                (3, '\(selfJID)', 3, NULL, 30), (4, '\(groupJID)', 1, 'Team', 50), (5, '\(otherGroupJID)', 1, 'Family', 40);
            INSERT INTO ZWAGROUPMEMBER VALUES (1, 4, 'a@s.whatsapp.net', 'Asha', NULL, 1),
                (2, 4, 'b@s.whatsapp.net', NULL, NULL, 1), (3, 4, 'c@s.whatsapp.net', NULL, NULL, 0),
                (4, 5, 'd@s.whatsapp.net', 'Dad', NULL, 1);
            INSERT INTO ZWAPROFILEPUSHNAME (ZJID, ZPUSHNAME) VALUES ('b@s.whatsapp.net', 'Bharat');
            """)
    }

    /// `member` is a ZWAGROUPMEMBER row; nil means the founder sent it. `reply` is the stanza id of the message this one
    /// quotes: it goes in field 5 of the media row's metadata, as WhatsApp writes it. Returns the row's Z_PK.
    @discardableResult
    func message(
        chat: Int, type: Int, text: String?, mediaPath: String? = nil, title: String? = nil, member: Int? = nil,
        date: Double = 1000, stanza: String? = nil, pk: Int? = nil, reply: String? = nil
    ) throws -> Int {
        let id = pk ?? Int.random(in: 1000...999_999)
        let textValue = text.map { "'\($0)'" } ?? "NULL"
        let fromMe = member == nil ? 1 : 0
        let memberValue = member.map(String.init) ?? "NULL"
        let stanzaValue = "'\(stanza ?? "S\(id)")'"
        var sql =
            """
            INSERT INTO ZWAMESSAGE(Z_PK, ZCHATSESSION, ZMESSAGEDATE, ZMESSAGETYPE, ZTEXT, ZISFROMME, ZGROUPMEMBER,
                ZSTANZAID) VALUES (\(id), \(chat), \(date), \(type), \(textValue), \(fromMe), \(memberValue), \(stanzaValue));
            """
        if type != 0 || reply != nil {
            let path = mediaPath.map { "'\($0)'" } ?? "NULL"
            let titleValue = title.map { "'\($0)'" } ?? "NULL"
            let metadata = reply.map { "X'" + Self.quotedStanzaMetadata($0) + "'" } ?? "NULL"
            sql += """
                INSERT INTO ZWAMEDIAITEM (ZMESSAGE, ZMEDIALOCALPATH, ZTITLE, ZMETADATA)
                VALUES (\(id), \(path), \(titleValue), \(metadata));
                """
        }
        try run(sql)
        return id
    }

    /// A protobuf blob with the quoted stanza id in field 5 and a quoted author in field 6, as hex.
    static func quotedStanzaMetadata(_ stanza: String) -> String {
        let author = Array("919800000002@s.whatsapp.net".utf8)
        let bytes =
            [UInt8(0x2A), UInt8(stanza.utf8.count)] + Array(stanza.utf8) + [0x32, UInt8(author.count)] + author
        return bytes.map { String(format: "%02X", $0) }.joined()
    }

    /// WhatsApp's Core Data store identity changed: the store is a new one.
    func changeStoreIdentity(to uuid: String) throws { try run("UPDATE Z_METADATA SET Z_UUID = '\(uuid)'") }

    func own(phone: String, lid: String) throws {
        let folder = container.appending(path: "Library/Preferences")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["OwnJabberID": phone, "lid": lid], format: .binary, options: 0)
        try data.write(to: folder.appending(path: "group.net.whatsapp.WhatsApp.shared.plist"))
    }

    func contacts(_ rows: [(lid: String, name: String)]) throws {
        let values = rows.map { "('\($0.lid)', NULL, '\($0.name)')" }.joined(separator: ", ")
        try run(
            """
            CREATE TABLE ZWAADDRESSBOOKCONTACT (Z_PK INTEGER PRIMARY KEY, ZLID TEXT, ZWHATSAPPID TEXT, ZFULLNAME TEXT);
            INSERT INTO ZWAADDRESSBOOKCONTACT (ZLID, ZWHATSAPPID, ZFULLNAME) VALUES \(values);
            """, in: "ContactsV2.sqlite")
    }

    func run(_ sql: String, in file: String = "ChatStorage.sqlite") throws {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let path = container.appending(path: file).path
        guard sqlite3_open(path, &db) == SQLITE_OK, sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw FixtureError()
        }
    }

    struct FixtureError: Error {}
}

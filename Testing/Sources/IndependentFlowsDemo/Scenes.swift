import Foundation
import SQLite3

@testable import WorkbenchCore
@testable import WorkbenchUI

let teamGroup = "120300000000000001@g.us"

/// A message of the fixture WhatsApp group: its words, whether the founder wrote it, and when.
struct ChatMessage {
    var text: String
    var fromMe = false
    var at: Date
}

/// A folder shaped like the Mac's WhatsApp data, with one group (Asha and Bharat) and these messages.
func whatsAppFolder(_ messages: [ChatMessage]) throws -> URL {
    let folder = try freshFolder()
    var sql = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZSESSIONTYPE INTEGER, ZPARTNERNAME TEXT,
            ZLASTMESSAGEDATE REAL);
        CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMESSAGEDATE REAL, ZMESSAGETYPE INTEGER,
            ZTEXT TEXT, ZISFROMME INTEGER, ZGROUPMEMBER INTEGER, ZSTANZAID TEXT, ZFLAGS INTEGER);
        CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMESSAGE INTEGER, ZMEDIALOCALPATH TEXT, ZTITLE TEXT,
            ZMETADATA BLOB);
        CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID TEXT);
        INSERT INTO Z_METADATA VALUES (1, 'STORE-DEMO-1');
        CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMEMBERJID TEXT, ZCONTACTNAME TEXT,
            ZFIRSTNAME TEXT, ZISACTIVE INTEGER);
        CREATE TABLE ZWAPROFILEPUSHNAME (Z_PK INTEGER PRIMARY KEY, ZJID TEXT, ZPUSHNAME TEXT);
        INSERT INTO ZWACHATSESSION VALUES (1, '\(teamGroup)', 1, 'Founders group', 2);
        INSERT INTO ZWAGROUPMEMBER VALUES (1, 1, 'a@s.whatsapp.net', 'Asha', NULL, 1),
            (2, 1, 'b@s.whatsapp.net', 'Bharat', NULL, 1);
        """
    for (index, message) in messages.enumerated() {
        let words = message.text.replacingOccurrences(of: "'", with: "''")
        sql += """

            INSERT INTO ZWAMESSAGE VALUES (\(10 + index), 1, \(message.at.timeIntervalSinceReferenceDate), 0, '\(words)',
                \(message.fromMe ? 1 : 0), \(message.fromMe ? "NULL" : "1"), 'S\(10 + index)', 0);
            """
    }
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open(folder.appending(path: "ChatStorage.sqlite").path, &db) == SQLITE_OK,
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    else { throw DemoError("could not write the WhatsApp fixture") }
    return folder
}

/// Noon of the day `days` before today: far from a day edge.
func noon(daysAgo days: Int) -> Date {
    let day = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
    return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
}

/// A mail message of the Deals label as the extension sends it, stored through the host as it would be.
func keepMail(_ text: String, from sender: String, thread: String, daysAgo: Int, in desk: Desk) throws {
    let context = MailContext(
        browser: "com.brave.Browser", url: "https://mail.google.com/mail/u/0/#label/Deals/\(thread)", label: "Deals",
        threadId: thread, messageId: "m-\(thread)")
    let mail = MailMessage(
        context: context, sender: sender, recipients: ["vc@fund.example"],
        sent: noon(daysAgo: daysAgo).timeIntervalSince1970, text: text)
    desk.clock.set(noon(daysAgo: daysAgo))
    defer { desk.clock.reset() }
    let reply = PageHost.answer(
        try JSONEncoder().encode(mail), store: desk.store, browser: "com.brave.Browser", owner: .success(Desk.owner))
    guard reply.kept else { throw DemoError("the mail was not kept: \(reply)") }
}

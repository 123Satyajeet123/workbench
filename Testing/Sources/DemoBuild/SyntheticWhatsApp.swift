import Foundation
import SQLite3

/// A WhatsApp container of invented people, in the format the real reader reads. One team group of the synthetic fund:
/// its name says synthetic, and so does a file beside the database.
enum SyntheticWhatsApp {
    static let groupJID = "120363999000000001@g.us"
    static let groupName = "Northlake deal desk (synthetic)"
    static let partner = "Meera Rao"

    struct Person: Equatable {
        let id: Int
        let jid: String
        let name: String
    }

    static let aditi = Person(id: 1, jid: "919000000001@s.whatsapp.net", name: "Aditi Verma")
    static let rohan = Person(id: 2, jid: "919000000002@s.whatsapp.net", name: "Rohan Kapoor")

    /// A line of the chat. `from` is nil for the partner, whose phone this is.
    struct Line: Equatable {
        let day: String
        let time: String
        let from: Person?
        let text: String
    }

    static let script: [Line] = [
        Line(
            day: "2026-11-12", time: "10:05", from: aditi,
            text:
                "Meera, Ledgerwick ka deck dekha? ARR 12 lakh hai, par deck me 40 lakh likha hai. Founder se poochna padega."
        ),
        Line(
            day: "2026-11-12", time: "10:12", from: nil,
            text: "Haan dekha. Aditi, tum Anvith ko mail karke ARR ka sahi number mango. Kal tak chahiye."),
        Line(
            day: "2026-11-12", time: "10:40", from: rohan,
            text:
                "Quillrate ne mail me team of 45 bola hai. LinkedIn pe 18 log dikh rahe hain. Main check karke Friday tak bataunga."
        ),
        Line(
            day: "2026-11-12", time: "15:30", from: aditi,
            text: "Suryabandh ki founder Gauri ne mail ka jawab diya. Gross margin pe abhi bhi clear nahi hai."),
        Line(
            day: "2026-11-13", time: "09:50", from: nil,
            text: "Rohan, Voltarth ka growth 30% MoM bola hai. Mujhe nahi lagta itna hai. Public data se verify karo."),
        Line(
            day: "2026-11-13", time: "11:20", from: rohan,
            text: "Voltarth ka asli number 9% lag raha hai. Deck ke slide 5 pe 30% likha hai. Note me daal deta hoon."),
        Line(
            day: "2026-11-13", time: "12:00", from: aditi,
            text: "Bolbhasha ka intro Rhea Menon (Kiranaloop) ne kiya hai. Warm intro hai, priority me rakhein?"),
        Line(
            day: "2026-11-13", time: "12:05", from: nil,
            text: "Haan, Bolbhasha ko hot rakho. Aditi, Kavya ke saath Monday ko 30 minute ka call fix karo."),
        Line(
            day: "2026-11-16", time: "10:15", from: aditi,
            text: "Kavya Bhandari ke saath call aaj 3 baje fix hai. Meeting link bhej diya."),
        Line(
            day: "2026-11-16", time: "10:30", from: nil,
            text: "Theek hai. Call se pehle Bolbhasha ka ARR 96 lakh aur 18% growth ek baar confirm kar lena."),
        Line(
            day: "2026-11-16", time: "16:45", from: rohan,
            text:
                "Nidanwala ne mail me 8 crore raise kiya bola hai. Hamare data me 2 crore hai. Founder se clarification chahiye."
        ),
        Line(
            day: "2026-11-16", time: "17:00", from: nil,
            text: "Rohan, Nidanwala ko ek chhota mail bhejo. Jab tak jawab nahi aata, usko pipeline me aage mat badhao."
        ),
        Line(
            day: "2026-11-17", time: "09:30", from: aditi,
            text:
                "Paynidhi ne UPI ke 800 lakh crore bole hain. NPCI ke hisaab se 284.7 lakh crore hai. Market size galat hai."
        ),
        Line(
            day: "2026-11-17", time: "09:45", from: nil,
            text: "Theek hai, usko claim galat mark karo. Founder ko ek baar mauka denge."),
        Line(
            day: "2026-11-17", time: "14:00", from: rohan,
            text: "Kistiwala pre-seed hai, sirf 5 customers. Hamari thesis ke liye bahut chhota. Pass karna chahiye?"),
        Line(
            day: "2026-11-17", time: "14:10", from: nil,
            text: "Pass karo, par ek polite mail bhejo. Do mahine baad dobara dekhenge."),
        Line(
            day: "2026-11-17", time: "18:20", from: aditi,
            text:
                "Dukanvault ne 1,200 distributors bole hain, asli number 240 hai. Mail aur deck me alag-alag numbers hain."
        ),
        Line(
            day: "2026-11-18", time: "10:00", from: nil,
            text: "Sabko yaad dila do: Friday ko deal review hai. Har hot deal pe ek paragraph chahiye."),
        Line(
            day: "2026-11-18", time: "10:05", from: rohan,
            text: "Theek hai. Main Ledgerwick, Bolbhasha aur Suryabandh pe likhunga."),
        Line(
            day: "2026-11-18", time: "10:07", from: aditi,
            text: "Main Voltarth aur Tallyra pe likhungi. Tallyra ka deck abhi tak nahi aaya."),
        Line(
            day: "2026-11-18", time: "17:40", from: nil,
            text: "Rohan, Suryabandh ka factory rooftop solar model samajh aaya? Kal subah mujhe 5 line me batao."),
        Line(
            day: "2026-11-19", time: "09:20", from: rohan,
            text:
                "Suryabandh: 2.6 crore run-rate, 16 months ka runway. Margin ka number abhi bhi nahi aaya. Gauri ko dobara mail kiya."
        ),
        Line(day: "2026-11-19", time: "11:00", from: aditi, text: "Tallyra ka deck aa gaya. Main check kar rahi hoon."),
        Line(
            day: "2026-11-19", time: "11:30", from: nil,
            text: "Badhiya. Aaj shaam tak sabka summary is group me daal do."),
    ]

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }

    static func date(of line: Line) -> Date {
        let parts = (line.day + "-" + line.time).split(whereSeparator: { $0 == "-" || $0 == ":" }).compactMap {
            Int($0)
        }
        return calendar.date(
            from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))!
    }

    static func sql(lines: [Line] = script) -> String {
        func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
        let last = lines.map { date(of: $0).timeIntervalSinceReferenceDate }.max() ?? 0
        let messages = lines.enumerated().map { index, line in
            let sender = line.from
            return "(\(index + 10), 1, \(date(of: line).timeIntervalSinceReferenceDate), 0, \(quoted(line.text)), "
                + "\(sender == nil ? 1 : 0), \(sender.map { String($0.id) } ?? "NULL"), 'SYN\(index + 10)')"
        }
        return """
            CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZSESSIONTYPE INTEGER, ZPARTNERNAME TEXT,
                ZLASTMESSAGEDATE REAL);
            CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMESSAGEDATE REAL, ZMESSAGETYPE INTEGER,
                ZTEXT TEXT, ZISFROMME INTEGER, ZGROUPMEMBER INTEGER, ZSTANZAID TEXT);
            CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMESSAGE INTEGER, ZMEDIALOCALPATH TEXT, ZTITLE TEXT,
                ZMETADATA BLOB);
            CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID TEXT);
            INSERT INTO Z_METADATA VALUES (1, 'SYNTHETIC-DEMO-STORE-1');
            CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMEMBERJID TEXT, ZCONTACTNAME TEXT,
                ZFIRSTNAME TEXT, ZISACTIVE INTEGER);
            CREATE TABLE ZWAPROFILEPUSHNAME (Z_PK INTEGER PRIMARY KEY, ZJID TEXT, ZPUSHNAME TEXT);
            INSERT INTO ZWACHATSESSION VALUES (1, '\(groupJID)', 1, \(quoted(groupName)), \(last));
            INSERT INTO ZWAGROUPMEMBER VALUES
                (\(aditi.id), 1, '\(aditi.jid)', \(quoted(aditi.name)), NULL, 1),
                (\(rohan.id), 1, '\(rohan.jid)', \(quoted(rohan.name)), NULL, 1);
            INSERT INTO ZWAMESSAGE VALUES \(messages.joined(separator: ",\n    "));
            """
    }

    struct WriteFailure: Error { let cause: String }

    static func write(to container: URL, lines: [Line] = script) throws {
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try Data("Every person and message here is synthetic. Made by demo-builder.\n".utf8)
            .write(to: container.appending(path: "SYNTHETIC.txt"))
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open(container.appending(path: "ChatStorage.sqlite").path, &db) == SQLITE_OK,
            sqlite3_exec(db, sql(lines: lines), nil, nil, nil) == SQLITE_OK
        else { throw WriteFailure(cause: db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database") }
    }
}

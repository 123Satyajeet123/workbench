import AppKit
import CaptureService
import Foundation
import SQLite3
import Synchronization
import WorkbenchCore

@testable import WorkbenchUI

func scratchFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "wbui-\(UUID().uuidString)")
}

func scratchStore(clock: @escaping @Sendable () -> Date = { Date() }) throws -> Store {
    try Store(directory: scratchFolder(), clock: clock)
}

@MainActor
func captureSettings(over store: Store? = nil) throws -> CaptureSettings {
    CaptureSettings(service: try CaptureService(store: try store ?? scratchStore()))
}

/// Answers with one JSON reply and remembers each input.
final class ScriptedModel: StructuredModel, Sendable {
    let name = "scripted"
    private let reply: String
    let inputs = Mutex<[String]>([])

    init(_ reply: String) { self.reply = reply }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        inputs.withLock { $0.append(input) }
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: "scripted-1",
            usage: Usage(inputTokens: 300, outputTokens: 40, costUSD: 0.02), reply: reply)
    }
}

extension OnboardingModel {
    func advance(to target: OnboardingScreen) {
        identityModel.identity.name = "Rhea"
        for _ in screens where screen != target {
            if screen == .team { teamModel.team.name = "Brave" }
            next()
        }
    }
}

/// Records each notification instead of showing it.
final class FakeNotifier: Notifier {
    var access = SystemAccess.allowed
    var posted: [(title: String, body: String)] = []

    func authorize() async -> SystemAccess { access }
    func post(title: String, body: String) async throws { posted.append((title, body)) }
}

/// A clock a test can move.
nonisolated final class TestClock: Sendable {
    private let value: Mutex<Date>
    init(_ start: Date) { value = Mutex(start) }
    var now: Date { value.withLock { $0 } }
    func set(_ date: Date) { value.withLock { $0 = date } }
}

extension Machine {
    /// A machine record for a model under test, as the store would hand it out.
    static func test(_ spec: HelperSpec, _ name: String, id: Int64 = 0) -> Machine {
        Machine(id: id, name: name, template: spec.task, spec: spec, state: .active)
    }
}

let teamJID = "120300000000000001@g.us"
let familyJID = "120300000000000002@g.us"

/// A WhatsApp container with a team group (Asha, Bharat) and a family group, and three team messages at `at`.
func whatsApp(at date: Date) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "wa-ui-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let seconds = date.timeIntervalSinceReferenceDate
    let sql = """
        CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID TEXT, ZSESSIONTYPE INTEGER, ZPARTNERNAME TEXT,
            ZLASTMESSAGEDATE REAL);
        CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMESSAGEDATE REAL, ZMESSAGETYPE INTEGER,
            ZTEXT TEXT, ZISFROMME INTEGER, ZGROUPMEMBER INTEGER);
        CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMESSAGE INTEGER, ZMEDIALOCALPATH TEXT, ZTITLE TEXT);
        CREATE TABLE ZWAGROUPMEMBER (Z_PK INTEGER PRIMARY KEY, ZCHATSESSION INTEGER, ZMEMBERJID TEXT, ZCONTACTNAME TEXT,
            ZFIRSTNAME TEXT, ZISACTIVE INTEGER);
        CREATE TABLE ZWAPROFILEPUSHNAME (Z_PK INTEGER PRIMARY KEY, ZJID TEXT, ZPUSHNAME TEXT);
        INSERT INTO ZWACHATSESSION VALUES (1, '\(teamJID)', 1, 'Team', 2), (2, '\(familyJID)', 1, 'Family', 1);
        INSERT INTO ZWAGROUPMEMBER VALUES (1, 1, 'a@s.whatsapp.net', 'Asha', NULL, 1),
            (2, 1, 'b@s.whatsapp.net', 'Bharat', NULL, 1);
        INSERT INTO ZWAMESSAGE VALUES (10, 1, \(seconds), 0, 'ki aaj kya kiya?', 1, NULL),
            (11, 1, \(seconds + 60), 0, 'login API done', 0, 1), (12, 2, \(seconds), 0, 'dinner at 8', 0, NULL);
        """
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open(folder.appending(path: "ChatStorage.sqlite").path, &db) == SQLITE_OK,
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    else { throw CocoaError(.fileWriteUnknown) }
    return folder
}

/// A reply type for model calls whose content a test does not read.
nonisolated struct Nothing: Decodable, Sendable {}

/// Answers with the reply whose key its instructions contain, so each brief or task reads differently. Replies can be
/// set after items exist, for replies that cite their ids.
final class KeyedModel: StructuredModel, Sendable {
    let name = "keyed"
    let replies: Mutex<[String: String]>
    let calls = Mutex(0)
    let inputs = Mutex<[String]>([])

    init(_ replies: [String: String]) { self.replies = Mutex(replies) }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        calls.withLock { $0 += 1 }
        inputs.withLock { $0.append(input) }
        let reply = replies.withLock { $0.first { instructions.contains($0.key) }?.value } ?? #"{"items":[]}"#
        let cited = Self.cite(reply, in: input)
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(cited.utf8)), model: "m", usage: Usage(), reply: cited)
    }

    /// `@Open PR@` in a reply becomes the number of the input line that holds "Open PR", as a model cites a line by
    /// what it says; lines keep their ids across days and readings, so a reply cannot hard-code them.
    static func cite(_ reply: String, in input: String) -> String {
        reply.replacing(#/@([^@"]+)@/#) { match in
            let words = String(match.output.1)
            let line = input.split(separator: "\n").first { $0.hasPrefix("[") && $0.contains(words) }
            return line.flatMap { $0.dropFirst().split(separator: "]").first }.map(String.init) ?? "0"
        }
    }
}

/// Adds a photo message from Asha with `text` drawn in it to a fixture container; returns its message id.
func addPhoto(_ text: String, to container: URL, at date: Date) throws -> Int64 {
    let image = NSImage(size: NSSize(width: 900, height: 160))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 900, height: 160).fill()
    (text as NSString).draw(
        at: NSPoint(x: 30, y: 55),
        withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black])
    image.unlockFocus()
    let file = container.appending(path: "Message/Media/shot.png")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
    try (rep?.representation(using: .png, properties: [:]) ?? Data()).write(to: file)
    let sql = """
        INSERT INTO ZWAMESSAGE VALUES (20, 1, \(date.timeIntervalSinceReferenceDate), 1, NULL, 0, 1);
        INSERT INTO ZWAMEDIAITEM (ZMESSAGE, ZMEDIALOCALPATH, ZTITLE) VALUES (20, 'Media/shot.png', NULL);
        """
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open(container.appending(path: "ChatStorage.sqlite").path, &db) == SQLITE_OK,
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    else { throw CocoaError(.fileWriteUnknown) }
    return 20
}

/// Adds a text message from Asha (or the founder when `member` is nil) to a fixture container.
func addMessage(_ id: Int64, _ text: String, member: Int? = 1, at date: Date, to container: URL) throws {
    let fromMe = member == nil ? 1 : 0
    let sql = """
        INSERT INTO ZWAMESSAGE VALUES (\(id), 1, \(date.timeIntervalSinceReferenceDate), 0, '\(text)', \(fromMe),
            \(member.map(String.init) ?? "NULL"));
        """
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    guard sqlite3_open(container.appending(path: "ChatStorage.sqlite").path, &db) == SQLITE_OK,
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    else { throw CocoaError(.fileWriteUnknown) }
}

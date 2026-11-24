import Foundation

@testable import WorkbenchCore

/// The erase on a big store: how long each door takes, and whether the bytes are gone. Lines are invented sentences of
/// random words from a small vocabulary, in 50 chats.
enum Scale {
    static let chats = 50

    static func run(lines: Int, in folder: URL, findings: Findings) async throws {
        print("\n== scale: \(lines) lines in \(chats) chats")
        let words = Words()
        let scene = try Scene(in: folder, words: words)
        let built = try timed { try fill(scene, lines: lines) }
        print("     built in \(seconds(built)) s; database \(megabytes(of: "workbench.sqlite", in: folder)) MB")
        let revoke = try await timedAsync {
            try await scene.record(
                [Scene.groupTombstone(chat: chat(0), stanza: "canary", at: scene.now)], chat: chat(0))
        }
        print("     revoke of one line: \(seconds(revoke)) s")
        let grant = try timed { try scene.store.eraseEvidence(.grant(kind: .whatsapp, label: chat(1))) }
        print("     erase of one chat (\(lines / chats) lines): \(seconds(grant)) s")
        let snapshot = try timed { try scene.store.snapshotIfDue() }
        print("     one snapshot (VACUUM INTO): \(seconds(snapshot)) s")
        let hits = ByteScan.hits(of: words.canary, under: scene.directory)
        for hit in hits { findings.leak("scale: canary in \(hit.file) at byte \(hit.offset), \(hit.place)") }
        findings.expect(hits.isEmpty, "scale: no byte of the revoked line is left in \(lines) lines")
        try scene.store.writer.close()
    }

    static func chat(_ index: Int) -> String { String(format: "1203000000000%05d@g.us", index) }

    private static func fill(_ scene: Scene, lines: Int) throws {
        let perChat = lines / chats
        scene.policy.allowList[.whatsapp] = Set((0..<chats).map(chat))
        try scene.store.savePolicy(scene.policy)
        let vocabulary = (0..<3000).map { "w\($0)x" }
        for index in 0..<chats {
            var start = 0
            while start < perChat {
                let batch = try (start..<min(start + 500, perChat)).map { number in
                    let text = (0..<12).map { _ in vocabulary.randomElement()! }.joined(separator: " ")
                    let stanza = index == 0 && number == 0 ? "canary" : "S\(number)"
                    let body = index == 0 && number == 0 ? "\(text) \(scene.words.canary)" : text
                    return try Scene.groupLine(chat: chat(index), stanza: stanza, text: body, at: scene.old)
                }
                try scene.record(batch, chat: chat(index))
                start += 500
            }
        }
    }

    private static func timed(_ body: () throws -> Void) throws -> Duration {
        try ContinuousClock().measure(body)
    }

    private static func timedAsync(_ body: () async throws -> Void) async throws -> Duration {
        try await ContinuousClock().measure(body)
    }

    private static func seconds(_ duration: Duration) -> String {
        String(format: "%.2f", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    private static func megabytes(of name: String, in folder: URL) -> Int {
        let size =
            (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: name).path)[.size] as? Int) ?? 0
        return size / 1_000_000
    }
}

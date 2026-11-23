import Foundation
import Synchronization
import Testing

@testable import LocalSources

@Suite struct VoiceTextTests {
    @Test func aVoiceNoteIsHeardOncePerVersionAndOneNotHeardIsTriedAgain() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appending(path: "note.opus")
        let later = folder.appending(path: "later.opus")
        try Data("a".utf8).write(to: note)
        try Data("b".utf8).write(to: later)
        let calls = Mutex<[String]>([])
        let ready = Mutex(false)
        let memo = VoiceText.Memo { url in
            calls.withLock { $0.append(url.lastPathComponent) }
            if url == later, !ready.withLock({ $0 }) { return nil }
            return "heard \(url.lastPathComponent)"
        }
        #expect(await memo.texts(in: [note, later]) == [note: "heard note.opus"])
        ready.withLock { $0 = true }
        #expect(await memo.texts(in: [note, later]) == [note: "heard note.opus", later: "heard later.opus"])
        #expect(calls.withLock { $0 }.filter { $0 == "note.opus" }.count == 1)
        #expect(calls.withLock { $0 }.filter { $0 == "later.opus" }.count == 2)
        #expect(await memo.texts(in: [folder.appending(path: "gone.opus")]).isEmpty)
    }

    @Test func aWhatsAppVoiceNoteComesWithItsFile() async throws {
        let fixture = try WhatsAppFixture()
        try Data("opus".utf8).write(to: fixture.container.appending(path: "Message/Media/note.opus"))
        try fixture.message(chat: 4, type: 3, text: nil, mediaPath: "Media/note.opus", member: 1)
        let entry = try #require(
            try await WhatsAppChatReader(container: fixture.container, chatJID: groupJID, policy: whatsappOn).entries()
                .first)
        #expect(entry.kind == .voiceNote)
        let file = fixture.container.appending(path: "Message/Media/note.opus").resolvingSymlinksInPath()
        #expect(entry.media == .file(file))
    }
}

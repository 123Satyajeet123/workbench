import Foundation
import Synchronization
import Testing
import WorkbenchCore

@testable import LocalSources

/// The watch keeps our copy current while the app runs, on fixture folders (never the live store).
@MainActor @Suite(.timeLimit(.minutes(1))) struct WhatsAppIngestWatchTests {
    typealias Rig = WhatsAppEvidenceTests.Rig
    static let period = Duration.milliseconds(300)

    private func waitUntil(_ seconds: Double = 10, _ condition: () throws -> Bool) async throws -> Bool {
        let end = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < end {
            if try condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try condition()
    }

    private func watch(_ rig: Rig) -> WhatsAppIngestWatch {
        WhatsAppIngestWatch(
            store: rig.store, owner: WhatsAppEvidenceTests.owner, container: rig.fixture.container, period: Self.period,
            latency: 0.1)
    }

    @Test func theStoreAndItsLogAreTheOnlyFilesThatCount() {
        #expect(WhatsAppIngestWatch.isStoreFile("/x/ChatStorage.sqlite"))
        #expect(WhatsAppIngestWatch.isStoreFile("/x/ChatStorage.sqlite-wal"))
        #expect(!WhatsAppIngestWatch.isStoreFile("/x/ChatStorage.sqlite-shm"))
        #expect(!WhatsAppIngestWatch.isStoreFile("/x/Message/Media/photo.jpg"))
        #expect(!WhatsAppIngestWatch.isStoreFile("/x/ContactsV2.sqlite"))
    }

    @Test func startingReadsTheAllowedChatsAndAChangeIsReadAgain() async throws {
        let rig = try Rig()
        let word = "zxq\(UInt32.random(in: 100_000...999_999))words"
        try rig.fixture.message(chat: 4, type: 0, text: word, member: 1, pk: 11)
        let watch = watch(rig)
        defer { watch.stop() }
        #expect(try await waitUntil { try rig.count("SELECT count(*) FROM evidence") == 1 }, "read at start")
        try rig.fixture.message(chat: 4, type: 0, text: "a later message", member: 1, stanza: "S12", pk: 12)
        #expect(
            try await waitUntil { try rig.count("SELECT count(*) FROM evidence") == 2 }, "read after the store changed")
    }

    @Test func aRevokeWhileTheAppRunsErasesTheTextWithinAPeriod() async throws {
        let rig = try Rig()
        let word = "zxq\(UInt32.random(in: 100_000...999_999))secret"
        try rig.fixture.message(chat: 4, type: 0, text: word, member: 1, pk: 11)
        let watch = watch(rig)
        defer { watch.stop() }
        #expect(try await waitUntil { try rig.copies(of: word) > 0 }, "stored first")
        let revoked = ContinuousClock.now
        try rig.fixture.run("UPDATE ZWAMESSAGE SET ZMESSAGETYPE = 14, ZTEXT = NULL WHERE Z_PK = 11")
        #expect(
            try await waitUntil(5) {
                try rig.copies(of: word) == 0 && rig.count("SELECT count(*) FROM evidence WHERE tombstone = 1") == 1
            })
        let took = ContinuousClock.now - revoked
        #expect(took < Self.period + .seconds(2), "about one period plus FSEvents latency and one read, took \(took)")
    }

    @Test func aChangeToAnotherFileOfTheContainerReadsNothing() async throws {
        let rig = try Rig()
        let reads = Counter()
        let watch = WhatsAppIngestWatch(
            store: rig.store, owner: WhatsAppEvidenceTests.owner, container: rig.fixture.container, period: Self.period,
            latency: 0.1,
            onIngest: { _ in reads.add() })
        defer { watch.stop() }
        #expect(try await waitUntil { reads.count == 1 }, "the one read at start")
        try Data("x".utf8).write(to: rig.fixture.container.appending(path: "Message/Media/photo.jpg"))
        try await Task.sleep(for: .seconds(1.2))
        #expect(reads.count == 1)
    }

    @Test func stoppedItReadsNoMore() async throws {
        let rig = try Rig()
        let reads = Counter()
        let watch = WhatsAppIngestWatch(
            store: rig.store, owner: WhatsAppEvidenceTests.owner, container: rig.fixture.container, period: Self.period,
            latency: 0.1,
            onIngest: { _ in reads.add() })
        #expect(try await waitUntil { reads.count == 1 })
        watch.stop()
        try rig.fixture.message(chat: 4, type: 0, text: "after stop", member: 1, pk: 13)
        try await Task.sleep(for: .seconds(1.2))
        #expect(reads.count == 1)
        #expect(try rig.count("SELECT count(*) FROM evidence") == 0)
    }
}

private final class Counter: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func add() { value.withLock { $0 += 1 } }
}

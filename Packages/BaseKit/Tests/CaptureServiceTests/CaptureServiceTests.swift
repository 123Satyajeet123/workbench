import Foundation
import LocalSources
import Synchronization
import Testing
import WorkbenchCore

import struct Kernel.PersonID

@testable import CaptureService

extension CaptureService {
    /// A service for a test, owned by a fixed test person.
    convenience init(store: Store) throws { try self.init(store: store, owner: .success(PersonID("test-owner"))) }
}

@MainActor
struct CaptureServiceTests {
    private func service() throws -> (CaptureService, Store) {
        let store = try Store(
            directory: FileManager.default.temporaryDirectory.appending(path: "cs-\(UUID().uuidString)"))
        return (try CaptureService(store: store), store)
    }

    @Test func dataOlderThanThirtyDaysIsDeletedAndNewerDataStays() async throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let now = Mutex(start)
        let store = try Store(
            directory: FileManager.default.temporaryDirectory.appending(path: "cs-\(UUID().uuidString)"),
            clock: { now.withLock { $0 } })
        let service = try CaptureService(store: store)
        let policy = CapturePolicy(switches: [.screen: true])
        var engine = CaptureEngine()
        for (days, window) in [(0.0, 1), (40.0, 2)] {
            let at = start.addingTimeInterval(days * 86_400)
            now.withLock { $0 = at }
            let snapshot = ScreenSnapshot(app: "Brave", bundleID: "b", windowID: window, title: "w\(window)", text: "")
            let batch = engine.observe(snapshot, idleSeconds: 0, policy: policy, at: at)
            try store.record(#require(batch))
        }
        await service.pruneIfDue(at: start.addingTimeInterval(41 * 86_400))
        #expect(try store.queries.activities(since: .distantPast).map(\.title) == ["w2"])
        #expect(service.problem == nil)
    }

    @Test func runTextOlderThanThirtyDaysIsDeletedWithTheRunKeptAsTheMeter() async throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let now = Mutex(start)
        let store = try Store(
            directory: FileManager.default.temporaryDirectory.appending(path: "cs-\(UUID().uuidString)"),
            clock: { now.withLock { $0 } })
        let service = try CaptureService(store: store)
        let model = RecordedModel(EmptyItemsModel(), store: store)
        var runs: [RunID] = []
        for days in [0.0, 40.0] {
            now.withLock { $0 = start.addingTimeInterval(days * 86_400) }
            runs.append(
                try await model.generate(
                    [String: JSONValue].self, schema: .object([]), task: "t", instructions: "", input: "chat text",
                    holding: [.whatsapp]
                ).run)
        }
        await service.pruneIfDue(at: start.addingTimeInterval(41 * 86_400))
        #expect(try runs.map { try store.queries.runText(of: $0) != nil } == [false, true])
        #expect(try store.queries.runs().count == 2)
    }

    @Test func aCallIsRefusedUntilSwitchedOnOrWhilePausedAndAsksFirstInPrivateMode() async throws {
        let (service, store) = try service()
        let brave = AudioApp(bundleID: "com.brave.Browser", name: "Brave", processes: [1])
        let hour = store.clock().addingTimeInterval(3600)
        await #expect(throws: CallStartError.denied(.sourceSwitchedOff)) { try await service.startCall(in: brave) }
        try service.update {
            $0.switches[.call] = true
            $0.mode = .paused(until: hour)
        }
        await #expect(throws: CallStartError.denied(.paused)) { try await service.startCall(in: brave) }
        try service.update { $0.mode = .privateMode(until: hour) }
        await #expect(throws: CallStartError.needsConfirmation) { try await service.startCall(in: brave) }
        try service.update {
            $0.denyList[.call] = ["com.brave.Browser"]
            $0.mode = .on
        }
        await #expect(throws: CallStartError.denied(.labelDenied)) { try await service.startCall(in: brave) }
        #expect(service.call == nil)
        #expect(try store.queries.recordings().isEmpty)
    }

}

/// Answers every call with an empty object.
private struct EmptyItemsModel: StructuredModel {
    let name = "empty"

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let value = try JSONDecoder().decode(T.self, from: Data("{}".utf8))
        return ModelAnswer(value: value, model: name, usage: Usage(), reply: "{}")
    }
}

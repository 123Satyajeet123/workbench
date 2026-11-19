import CaptureService
import Foundation
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
            usage: Usage(inputTokens: 300, outputTokens: 40, costUSD: 0.02))
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
    var access = NotificationAccess.allowed
    var posted: [(title: String, body: String)] = []

    func authorize() async -> NotificationAccess { access }
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

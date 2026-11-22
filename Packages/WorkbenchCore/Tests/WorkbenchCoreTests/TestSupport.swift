import Foundation
import Synchronization

@testable import WorkbenchCore

let t0 = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

func day(_ offset: Double, from base: Date = t0) -> Date { base.addingTimeInterval(offset * 86_400) }

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "wbcore-\(UUID().uuidString)")
}

func makeStore(clock: @escaping @Sendable () -> Date = { t0 }) throws -> Store {
    try Store(directory: temporaryDirectory(), clock: clock)
}

func grant(_ kind: SourceKind, label: String? = nil, at now: Date = t0) -> CaptureGrant {
    CapturePolicy(switches: [kind: true], allowList: label.map { [kind: [$0]] } ?? [:])
        .authorize(CaptureRequest(kind: kind, label: label), at: now).grant!
}

/// Answers every call with one fixed JSON reply, or an error, and remembers each input.
final class ScriptedModel: StructuredModel, Sendable {
    let name = "scripted"
    private let reply: Result<String, StructuredModelError>
    private let usage: Usage
    let inputs = Mutex<[String]>([])

    init(_ reply: String, usage: Usage = Usage(inputTokens: 100, outputTokens: 20, costUSD: 0.01)) {
        self.reply = .success(reply)
        self.usage = usage
    }

    init(failing error: StructuredModelError) {
        reply = .failure(error)
        usage = Usage()
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        inputs.withLock { $0.append(input) }
        let text = try reply.get()
        let value = try JSONDecoder().decode(T.self, from: Data(text.utf8))
        return ModelAnswer(value: value, model: "scripted-1", usage: usage, reply: text)
    }
}

extension CaptureDecision {
    var denial: DenyReason? { if case .deny(let reason) = self { reason } else { nil } }
    var confirmation: PendingConfirmation? { if case .confirm(let pending) = self { pending } else { nil } }
}

extension Store {
    /// A new handle on the same folder is what a restart gives the app.
    func reopened(clock: @escaping @Sendable () -> Date = { t0 }) throws -> Store {
        try Store(directory: directory, clock: clock)
    }
}

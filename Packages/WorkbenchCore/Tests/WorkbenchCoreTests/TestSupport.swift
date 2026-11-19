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
    /// True for a reply no schema-bound model can give, to test a check that does not rely on the schema.
    private let offSchema: Bool
    let inputs = Mutex<[String]>([])

    init(
        _ reply: String, offSchema: Bool = false,
        usage: Usage = Usage(inputTokens: 100, outputTokens: 20, costUSD: 0.01)
    ) {
        self.reply = .success(reply)
        self.offSchema = offSchema
        self.usage = usage
    }

    init(failing error: StructuredModelError) {
        reply = .failure(error)
        offSchema = false
        usage = Usage()
    }

    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        inputs.withLock { $0.append(input) }
        let text = try reply.get()
        guard try offSchema || schema.accepts(JSONSerialization.jsonObject(with: Data(text.utf8))) else {
            throw StructuredModelError.invalidReply("the scripted reply does not fit the schema")
        }
        let value = try JSONDecoder().decode(T.self, from: Data(text.utf8))
        return ModelAnswer(value: value, model: "scripted-1", usage: usage)
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

extension JSONSchema {
    /// Whether a decoded JSON value fits this schema as the CLIs enforce it: every property present, no other, each
    /// of the right type. A scripted reply must pass, so no test feeds the code a reply the real model cannot give.
    func accepts(_ value: Any) -> Bool {
        let isBool = { (number: NSNumber) in CFGetTypeID(number) == CFBooleanGetTypeID() }
        switch self {
        case .object(let properties):
            guard let object = value as? [String: Any], Set(object.keys) == Set(properties.map(\.name)) else {
                return false
            }
            return properties.allSatisfy { property in object[property.name].map(property.schema.accepts) ?? false }
        case .array(let element): return (value as? [Any])?.allSatisfy(element.accepts) ?? false
        case .string: return value is String
        case .boolean: return (value as? NSNumber).map(isBool) ?? false
        case .integer:
            guard let number = value as? NSNumber, !isBool(number) else { return false }
            return number.doubleValue == number.doubleValue.rounded()
        case .number: return (value as? NSNumber).map { !isBool($0) } ?? false
        case .enumeration(let values): return (value as? String).map(values.contains) ?? false
        }
    }
}

import Foundation

extension Run {
    /// Why a failed run failed. A kind comes from a typed source (an error type, or the plan limits the CLI reports),
    /// never from the words of a message.
    public enum Failure: String, Sendable, CaseIterable {
        case limit, timedOut, notInstalled, noAPIKey, unsafePlan, other
    }
}

/// An error that knows its kind of failure.
public protocol ClassifiedFailure: Error {
    var failure: Run.Failure { get }
    /// When the limit lifts, as the source says. Nil when it does not say.
    var resetsAt: Date? { get }
}

extension ClassifiedFailure {
    public var resetsAt: Date? { nil }
}

/// What a failed call does next, as data.
public struct FailurePolicy: Sendable {
    /// A timed-out call is tried again `timeOutRetries` times. The wait before a retry is drawn from
    /// 0..<`retryWindowSeconds`: "Full Jitter" of the AWS Architecture Blog. A limit whose reset the source did not
    /// give stops calls for `limitWithoutResetSeconds`.
    public var settings = RunSettings.standard
    public var wait: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// A number in 0..<1.
    public var jitter: @Sendable () -> Double = { .random(in: 0..<1) }

    public init() {}

    func waitBeforeRetry() async throws { try await wait(.seconds(settings.retryWindowSeconds) * jitter()) }
}

/// A call refused because the plan is at its limit. Nothing is sent, and no run is made.
public struct ModelPausedError: Error, Equatable, LocalizedError {
    public var plan: String
    public var until: Date

    public var errorDescription: String? {
        "Your \(plan.capitalized) plan is at its limit. Workbench makes no model call until "
            + until.formatted(date: .abbreviated, time: .shortened) + "."
    }
}

extension Store {
    private static func pauseKey(plan: String) -> String { "model.pause.\(plan)" }

    /// Every caller of the plan stops until `until`. The pause is a row of the store, so all machines share it.
    func pauseModel(plan: String, until: Date) throws {
        try saveState(until.stored, forKey: Self.pauseKey(plan: plan))
    }

    public func pausedUntil(plan: String) -> Date? {
        guard let text = (try? queries.state(forKey: Self.pauseKey(plan: plan))).flatMap({ $0 }),
            let until = try? Date(text, strategy: .iso8601), until > clock()
        else { return nil }
        return until
    }

    /// The one point that refuses a call before it starts: no yes to the terms, or a plan at its limit.
    func requireModelAccess(for model: any StructuredModel) throws {
        try requireModelTerms(for: model)
        if let plan = model.planName, let until = pausedUntil(plan: plan) {
            throw ModelPausedError(plan: plan, until: until)
        }
    }

    func pauseIfLimited(_ model: any StructuredModel, by error: any Error, policy: FailurePolicy) throws {
        guard let plan = model.planName, let failure = error as? any ClassifiedFailure, failure.failure == .limit
        else { return }
        try pauseModel(plan: plan, until: failure.resetsAt ?? clock() + policy.settings.limitWithoutResetSeconds)
    }
}

/// A failed call that the model's source had already counted: `usage` is what the CLI reported on its result line.
/// A failure with no result line (a time-out kill, a crash) is not wrapped: its usage is unknown, not zero.
public struct ChargedFailure: ClassifiedFailure, LocalizedError {
    public let cause: any Error
    public let usage: Usage

    public init(_ cause: any Error, usage: Usage) {
        self.cause = cause
        self.usage = usage
    }

    public var failure: Run.Failure { (cause as? any ClassifiedFailure)?.failure ?? .other }
    public var resetsAt: Date? { (cause as? any ClassifiedFailure)?.resetsAt }
    public var errorDescription: String? { cause.localizedDescription }

    /// The error a caller of the model should see, and the usage the failure carried, if any.
    static func split(_ error: any Error) -> (cause: any Error, usage: Usage?) {
        guard let charged = error as? ChargedFailure else { return (error, nil) }
        return (charged.cause, charged.usage)
    }
}

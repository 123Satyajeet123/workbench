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
    /// A timed-out call is tried again this many times.
    public var timeOutRetries = 1
    /// The wait before a retry is drawn from 0..<`retryWindow`: "Full Jitter" of the AWS Architecture Blog.
    public var retryWindow = Duration.seconds(10)
    /// How long calls stop at a limit whose reset the source did not give.
    public var limitWithoutReset: TimeInterval = 3600
    public var wait: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    /// A number in 0..<1.
    public var jitter: @Sendable () -> Double = { .random(in: 0..<1) }

    public init() {}

    func waitBeforeRetry() async throws { try await wait(retryWindow * jitter()) }
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
        try pauseModel(plan: plan, until: failure.resetsAt ?? clock() + policy.limitWithoutReset)
    }
}

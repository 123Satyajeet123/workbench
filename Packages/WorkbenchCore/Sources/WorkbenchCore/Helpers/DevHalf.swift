import Foundation

/// The two halves of the dev days. A machine learns from the marks of learn days, and a new version is judged on the
/// marks of trial days, so no item that shaped an edit can vote for it. The date alone decides, with a hash other
/// than the one `EvalSplit` uses. Held-out days belong to neither half.
public enum DevHalf: Sendable, CaseIterable {
    case learn
    case trial

    public init?(_ day: WorkDay) {
        guard EvalSplit(day) == .dev else { return nil }
        let second = UInt8(Digest.sha256(day.description).dropFirst(2).prefix(2), radix: 16) ?? 0
        self = second % 2 == 0 ? .learn : .trial
    }
}

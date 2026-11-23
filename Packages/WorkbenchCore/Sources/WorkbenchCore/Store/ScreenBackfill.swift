import Foundation
import GRDB
import Kernel

/// What the move of old window stretches into evidence lines writes and refuses. Counts only.
public struct ScreenBackfillCounts: Sendable, Equatable {
    /// Closed stretches found in the old activity rows, too short ones left out.
    public var stretches = 0
    /// Stretches the app's consent allows now: each becomes a line.
    public var written = 0
    /// Stretches of an app the consent does not allow now: they are not moved.
    public var refusedConsent = 0
}

/// The old screen rows. Window rows hold times on windows, which a machine read as numbered sessions and cited by the
/// id of the row that opened them; they move to lines, and the old id is mapped to the new line. Text rows have no
/// reader and are not moved: they stay in the capture log until the retention removes them.
extension Store {
    /// Every closed stretch of the old activity rows, oldest first, with the opener's row id.
    private func oldStretches() throws -> [ScreenSession] {
        var stretches = ScreenStretches()
        var closed: [ScreenSession] = []
        for activity in try queries.activities(from: .distantPast, to: .distantFuture) {
            guard let id = activity.id else { continue }
            closed += stretches.feed(activity, id: id).map { [$0] } ?? []
        }
        return closed.filter { $0.end.timeIntervalSince($0.start) >= Sessions.shortest }
    }

    private func screenGrant(for bundleID: String, in policy: CapturePolicy) -> CaptureGrant? {
        policy.authorize(CaptureRequest(kind: .screen, label: bundleID), at: clock()).grant
    }

    /// What `moveScreenStretchesToEvidence` would write and refuse now. Changes nothing, reads no text.
    public func previewScreenBackfill() throws -> ScreenBackfillCounts {
        let policy = try currentPolicy()
        return try Self.counts(of: oldStretches()) { screenGrant(for: $0, in: policy) != nil }
    }

    private static func counts(of stretches: [ScreenSession], allowed: (String) -> Bool) -> ScreenBackfillCounts {
        var counts = ScreenBackfillCounts()
        counts.stretches = stretches.count
        for stretch in stretches {
            if allowed(stretch.bundleID) { counts.written += 1 } else { counts.refusedConsent += 1 }
        }
        return counts
    }

    /// Writes the old stretches the consent allows as evidence lines through the one writer, and maps their old ids
    /// (`activity`). The old rows stay: the capture log shows them until the retention removes them. Safe to run again:
    /// a line already stored is only seen again.
    @discardableResult
    public func moveScreenStretchesToEvidence(owner: PersonID) throws -> ScreenBackfillCounts {
        let policy = try currentPolicy()
        let stretches = try oldStretches()
        for stretch in stretches {
            guard let grant = screenGrant(for: stretch.bundleID, in: policy),
                let reading = ScreenEvidence.reading(of: stretch, grant: grant, mapsLegacyRef: true)
            else { continue }
            _ = try record(reading, of: .screenWindow, owner: owner)
        }
        return Self.counts(of: stretches) { screenGrant(for: $0, in: policy) != nil }
    }
}

extension ScreenBackfillCounts {
    /// What the move would write and refuse on a copy of the store in `directory`. Counts only.
    public static func preview(onCopyOf directory: URL) throws -> ScreenBackfillCounts {
        try Store.withCopy(of: directory) { try $0.previewScreenBackfill() }
    }
}

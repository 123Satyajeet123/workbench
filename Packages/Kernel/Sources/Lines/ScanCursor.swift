// Source: built (research E-R3 §8.3: a cursor by row number, never by date; a trailing window by date for edits; a
// changed store id voids the cursor). Research E-R2 §4.2 step 6: old row numbers map to lines only on the first
// read, while the numbers still match. Review M1 step 2a H1, M7, L6.

import Foundation

/// Where a read of one container of a row-numbered source stopped: the store's identity, the highest row number read,
/// and when the read happened. A source that renumbers its rows (a new store id) invalidates it.
public struct ScanCursor: Codable, Hashable, Sendable {
    public var storeID: String
    public var lastRow: Int64
    public var readAt: Date

    public init(storeID: String, lastRow: Int64, readAt: Date) {
        self.storeID = storeID
        self.lastRow = lastRow
        self.readAt = readAt
    }

    /// The cursor to keep when `stored` is already there: inside one store neither field moves back, so two reads that
    /// finish out of order cannot undo each other. Another store id replaces the stored cursor.
    public func advanced(from stored: ScanCursor?) -> ScanCursor {
        guard let stored, stored.storeID == storeID else { return self }
        return ScanCursor(storeID: storeID, lastRow: max(lastRow, stored.lastRow), readAt: max(readAt, stored.readAt))
    }
}

/// What the store kept for one container before a read: its cursor, and whether the old citation ids of its rows were
/// ever mapped. The second outlives an erase, so a later consent never maps the numbers of a changed store.
public struct ScanState: Sendable, Equatable {
    public var cursor: ScanCursor?
    public var legacyMapped: Bool
    /// The stored cursor could not be read; `cursor` is nil, so this container is read from the start.
    public var cursorWasCorrupt: Bool

    public init(cursor: ScanCursor? = nil, legacyMapped: Bool = false, cursorWasCorrupt: Bool = false) {
        self.cursor = cursor
        self.legacyMapped = legacyMapped
        self.cursorWasCorrupt = cursorWasCorrupt
    }
}

/// What one read asks of the source: the rows numbered above `after`, the rows dated at or after `rescanSince` (the
/// trailing window, where an edit can still happen), and, for a source that can delete a message for everyone, every
/// deleted row whatever its age.
public struct ScanPlan: Equatable, Sendable {
    public var after: Int64
    public var rescanSince: Date
    /// Whether the row numbers of this read are the numbers old citations used: only until they were mapped once.
    public var mapsLegacyRefs: Bool
}

public enum Scan {
    /// The trailing window for edits of a row-numbered chat source. WhatsApp limits an edit to minutes; three days
    /// leaves a wide margin.
    public static let chatEditWindow: TimeInterval = 3 * 86_400

    /// The window starts at the last read, not at now: a Mac that was closed for a week still sees the edits made
    /// while it was closed.
    public static func plan(state: ScanState, storeID: String, now: Date, window: TimeInterval) -> ScanPlan {
        let valid = state.cursor.flatMap { $0.storeID == storeID ? $0 : nil }
        return ScanPlan(
            after: valid?.lastRow ?? 0, rescanSince: (valid?.readAt ?? now).addingTimeInterval(-window),
            mapsLegacyRefs: !state.legacyMapped)
    }

    /// The cursor after a read. `highestRow` is the highest row number the read returned, of any type (a skipped row
    /// is read once, not every time).
    public static func cursor(after plan: ScanPlan, storeID: String, highestRow: Int64?, readAt: Date) -> ScanCursor {
        ScanCursor(storeID: storeID, lastRow: max(plan.after, highestRow ?? plan.after), readAt: readAt)
    }
}

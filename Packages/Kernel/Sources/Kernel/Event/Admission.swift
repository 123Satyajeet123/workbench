// Source: built (research K7 §2.4 quarantine rule; review 1 F7: quarantine applies to events before the ledger).

extension HybridClock {
    public enum Admission: Hashable, Sendable {
        /// The event's stamp was merged into the clock; the event may go to the ledger.
        case admitted(Event)
        /// The event's stamp is too far ahead of the wall clock. The clock did not move; the caller keeps the event
        /// and offers it again once the wall clock reaches `untilWallMillis`.
        case quarantined(Event, untilWallMillis: Int64)
    }

    /// Applies this clock's quarantine to an incoming event, before the ledger sees it. The ledger itself never reads
    /// the wall clock.
    public mutating func admit(_ event: Event, wallMillis: Int64) -> Admission {
        switch receive(event.header.hlc, wallMillis: wallMillis) {
        case .merged: .admitted(event)
        case .quarantined(let until): .quarantined(event, untilWallMillis: until)
        }
    }
}

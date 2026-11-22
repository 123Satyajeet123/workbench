// Source: built (research 48 §1: ties by (hlc, device, numeric seq); replaces the string tie-break of judgment-pilot
// Packages/WorkbenchCore/Sources/WorkbenchCore/Team/Sync/Received.swift:50).

/// The total order of events for projections: stamp, then device bytes, then the sequence as a number, then label
/// and id. Two different events never tie.
public struct EventOrder: Comparable, Sendable {
    private let key: (HybridTimestamp, DeviceID, UInt64, LabelID, EventID)

    public init(_ header: EventHeader) {
        key = (header.hlc, header.stream.device, header.sequence, header.stream.label, .sha256(header.signedBytes))
    }

    public static func < (lhs: EventOrder, rhs: EventOrder) -> Bool { lhs.key < rhs.key }
    public static func == (lhs: EventOrder, rhs: EventOrder) -> Bool { lhs.key == rhs.key }
}

// Source: built (research K7 §6.1: a 16-byte label id in the signed header; 45 §4 widens the digest from 8 to 16 bytes).

/// A label, named by the first 16 bytes of SHA-256 over its sorted sources and classes. Equal labels have equal ids
/// however they were built; any other source or class gives another id.
public struct LabelID: FixedBytes {
    public static let count = 16
    public let bytes: [UInt8]

    public init?(bytes: [UInt8]) {
        guard bytes.count == Self.count else { return nil }
        self.bytes = bytes
    }

    fileprivate init(truncating digest: Digest) { bytes = Array(digest.bytes.prefix(Self.count)) }
}

extension Label {
    public var id: LabelID {
        let sourceBytes = sources.sorted().map(\.bytes)
        let classBytes = classes.sorted().map(\.utf8Bytes)
        let parts = [Framing.bytes("sources", sourceBytes), Framing.bytes("classes", classBytes)]
        return LabelID(truncating: .framed("workbench.label.v1", parts))
    }
}

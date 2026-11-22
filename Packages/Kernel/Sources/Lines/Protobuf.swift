// Source: built (research E-R3 §4: `ZWAMEDIAITEM.ZMETADATA` is protobuf; field 5 holds the quoted stanza id). The wire
// format is Google's Protocol Buffers encoding (the language guide's "Encoding" page).

/// The length-delimited fields of one protobuf message, read from its wire format. A blob that does not parse to its
/// end gives no field: a half-read blob is not trusted.
public enum Protobuf {
    /// The bytes of the first length-delimited field with this number, or nil when it is absent or the blob is
    /// malformed.
    public static func firstBytes(field number: UInt64, in blob: [UInt8]) -> [UInt8]? {
        var position = 0
        var found: [UInt8]?
        while position < blob.count {
            guard let tag = varint(blob, &position) else { return nil }
            switch tag & 7 {
            case 0:
                guard varint(blob, &position) != nil else { return nil }
            case 1:
                position += 8
            case 2:
                guard let length = varint(blob, &position), length <= UInt64(blob.count - position) else { return nil }
                let end = position + Int(length)
                if tag >> 3 == number, found == nil { found = Array(blob[position..<end]) }
                position = end
            case 5:
                position += 4
            default:
                return nil
            }
            guard position <= blob.count else { return nil }
        }
        return found
    }

    /// The text of the first length-delimited field with this number, when it is non-empty valid UTF-8.
    public static func firstText(field number: UInt64, in blob: [UInt8]) -> String? {
        guard let bytes = firstBytes(field: number, in: blob), !bytes.isEmpty else { return nil }
        return String(validating: bytes, as: UTF8.self)
    }

    private static func varint(_ blob: [UInt8], _ position: inout Int) -> UInt64? {
        var value: UInt64 = 0
        for shift in stride(from: 0, to: 70, by: 7) {
            guard position < blob.count else { return nil }
            let byte = blob[position]
            position += 1
            value |= UInt64(byte & 0x7F) << UInt64(shift)
            if byte & 0x80 == 0 { return value }
        }
        return nil
    }
}

/// Where the quoted message's stanza id sits in a media row's metadata.
public enum WhatsAppReply {
    public static let quotedStanzaField: UInt64 = 5

    /// The stanza id of the message that this one replies to, from the metadata blob of its media row.
    public static func quotedStanzaID(metadata: [UInt8]) -> String? {
        Protobuf.firstText(field: quotedStanzaField, in: metadata)
    }
}

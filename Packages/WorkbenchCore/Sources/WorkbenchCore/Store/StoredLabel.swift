import Foundation
import Kernel

/// A label as the item table keeps it: its sources as hex text and its classes, so a later join can start from it.
struct StoredLabel: Codable, Equatable {
    var sources: [String]
    var classes: [String]

    init(_ label: Label) {
        sources = label.sources.sorted().map(\.description)
        classes = label.classes.sorted().map(\.rawValue)
    }

    /// The label this holds. A source or class that cannot be read is a stored value this version cannot read.
    func label() throws -> Label {
        let ids = try sources.map { text in
            guard let id = SourceID(bytes: Self.bytes(hex: text)) else { throw StoredValueError("label") }
            return id
        }
        let classes = try classes.map { text in
            do { return try SourceClass(text) } catch { throw StoredValueError("label") }
        }
        do { return try Label(sources: Set(ids), classes: Set(classes)) } catch { throw StoredValueError("label") }
    }

    private static func bytes(hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count - 1, by: 2).compactMap { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
        }
    }
}

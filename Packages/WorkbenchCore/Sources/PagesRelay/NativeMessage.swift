import Foundation

/// Chrome's native messaging frame: a 4-byte length in native byte order (little-endian on Macs), then UTF-8 JSON.
public enum NativeMessage {
    /// Larger messages are refused. A page's text is far smaller; a deck travels in chunks that fit here. A browser
    /// allows 1 MiB from a host and 64 MiB to it.
    public static let maximumLength = 1024 * 1024

    public enum Failure: Error, Equatable {
        case truncated
        case tooLong(Int)
    }

    /// What one read of a frame found.
    public enum Incoming: Equatable {
        case message(Data)
        /// The input ended before a frame began.
        case end
        case broken(Failure)
    }

    /// The message at the start of `data`, and how many bytes it took; nil when `data` is empty.
    public static func first(in data: Data) throws -> (message: Data, consumed: Int)? {
        guard !data.isEmpty else { return nil }
        guard data.count >= 4 else { throw Failure.truncated }
        let length = length(ofHeader: data.prefix(4))
        guard length <= maximumLength else { throw Failure.tooLong(length) }
        guard data.count >= 4 + length else { throw Failure.truncated }
        let start = data.startIndex + 4
        return (data[start..<start + length], 4 + length)
    }

    /// The next frame from a source that gives exactly the bytes asked for, or fewer when it ends.
    public static func next(read: (Int) -> Data) -> Incoming {
        let header = read(4)
        guard !header.isEmpty else { return .end }
        guard header.count == 4 else { return .broken(.truncated) }
        let length = length(ofHeader: header)
        guard length <= maximumLength else { return .broken(.tooLong(length)) }
        let message = read(length)
        return message.count == length ? .message(message) : .broken(.truncated)
    }

    public static func frame(_ message: Data) -> Data {
        let length = UInt32(message.count)
        return Data((0..<4).map { UInt8(truncatingIfNeeded: length >> (8 * $0)) }) + message
    }

    private static func length(ofHeader header: Data) -> Int {
        header.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
    }
}

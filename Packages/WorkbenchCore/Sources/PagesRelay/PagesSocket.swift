import Darwin
import Foundation

/// The Unix domain socket that carries each browser message from the native host to the app. The app listens; the
/// host connects. This file is shared by both and holds no store code.
public enum PagesSocket {
    public static let fileName = "pages.sock"

    public enum Failure: Error, Equatable {
        /// A socket path must fit in `sockaddr_un`.
        case pathTooLong(Int)
        case system(String, Int32)
    }

    public static func path(in folder: URL) -> String { folder.appending(path: fileName).path }

    public static func address(of path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count <= capacity else { throw Failure.pathTooLong(bytes.count - 1) }
        withUnsafeMutableBytes(of: &address.sun_path) { target in
            for (index, byte) in bytes.enumerated() { target[index] = UInt8(bitPattern: byte) }
        }
        return address
    }

    /// A new stream socket that never raises SIGPIPE: a write to a closed peer fails with an error instead.
    public static func makeSocket() throws -> Int32 {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure.system("socket", errno) }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return descriptor
    }

    /// A connection to the app, or nil when no app listens on `path`.
    public static func connect(to path: String) -> Int32? {
        guard var address = try? address(of: path), let descriptor = try? makeSocket() else { return nil }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    /// Exactly `count` bytes, or fewer when the peer closed.
    public static func read(_ descriptor: Int32, count: Int) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: min(count, 64 * 1024))
        while data.count < count {
            let got = Darwin.read(descriptor, &buffer, min(buffer.count, count - data.count))
            if got < 0 && errno == EINTR { continue }
            guard got > 0 else { break }
            data += buffer.prefix(got)
        }
        return data
    }

    /// Whether all of `data` was written.
    @discardableResult
    public static func write(_ descriptor: Int32, _ data: Data) -> Bool {
        var rest = data[...]
        while !rest.isEmpty {
            let wrote = rest.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
            if wrote < 0 && errno == EINTR { continue }
            guard wrote > 0 else { return false }
            rest = rest.dropFirst(wrote)
        }
        return true
    }
}

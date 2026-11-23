import Darwin
import Dispatch
import Foundation
import Synchronization

/// The app's end of the native host's socket. The browser extension talks to the host process; the host passes each
/// message here; this app answers it with its own store, the only one open for writing. The app holds the
/// `StoreLock` before it starts a listener, so the socket of a dead app is safe to replace.
public final class PageHostListener: Sendable {
    public enum Failure: Error, Equatable {
        case cannotListen(String, Int32)
    }

    private static let backlog: Int32 = 8

    private let path: String
    private let source: any DispatchSourceRead
    private let sessions = Sessions()

    /// Only a process of `user` may connect: the person who runs the app.
    public init(path: String, store: Store, user: uid_t = geteuid()) throws {
        unlink(path)
        let descriptor = try Self.listen(on: path)
        self.path = path
        let queue = DispatchQueue(label: "workbench.pages")
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        let sessions = sessions
        source.setEventHandler {
            Self.acceptAll(on: descriptor, user: user, sessions: sessions, store: store)
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
        unlink(path)
        sessions.endAll()
    }

    /// The connections being served, so stopping the listener ends them: a host then finds the app gone.
    private final class Sessions: Sendable {
        private let open = Mutex<Set<Int32>>([])

        func begin(_ client: Int32) { open.withLock { _ = $0.insert(client) } }

        func end(_ client: Int32) {
            open.withLock { _ = $0.remove(client) }
            close(client)
        }

        func endAll() {
            open.withLock { clients in
                for client in clients { shutdown(client, SHUT_RDWR) }
            }
        }
    }

    private static func listen(on path: String) throws -> Int32 {
        var address = try PagesSocket.address(of: path)
        let descriptor = try PagesSocket.makeSocket()
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(descriptor, backlog) == 0,
            fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0
        else {
            let reason = errno
            close(descriptor)
            throw Failure.cannotListen(path, reason)
        }
        return descriptor
    }

    private static func acceptAll(
        on listener: Int32, user: uid_t, sessions: Sessions, store: Store
    ) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            guard isPeer(client, user: user), fcntl(client, F_SETFL, 0) == 0 else {
                close(client)
                continue
            }
            sessions.begin(client)
            Thread.detachNewThread {
                PageHost.serve(
                    read: { PagesSocket.read(client, count: $0) },
                    write: { PagesSocket.write(client, $0) }, store: store)
                sessions.end(client)
            }
        }
    }

    private static func isPeer(_ client: Int32, user: uid_t) -> Bool {
        var peer = uid_t()
        var group = gid_t()
        return getpeereid(client, &peer, &group) == 0 && peer == user
    }
}

extension PageHostListener.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cannotListen: "Workbench could not open the local socket that the browser extension sends to."
        }
    }
}

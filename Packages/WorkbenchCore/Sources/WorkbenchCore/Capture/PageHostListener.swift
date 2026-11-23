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

    /// Only a process of `user` may connect: the person who runs the app. `browserOf` names the browser behind a
    /// connection; the default reads the process tree.
    public init(
        path: String, store: Store, user: uid_t = geteuid(),
        browserOf: (@Sendable (Int32) -> String?)? = nil
    ) throws {
        unlink(path)
        let descriptor = try Self.listen(on: path)
        self.path = path
        let queue = DispatchQueue(label: "workbench.pages")
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        let sessions = sessions
        source.setEventHandler {
            Self.acceptAll(
                on: descriptor, user: user, sessions: sessions, store: store,
                browserOf: browserOf ?? PeerBrowser.bundleID(ofPeer:))
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
        unlink(path)
        sessions.endAll()
    }

    /// The connections being served, so stopping the listener ends them: a host then finds the app gone. A connection
    /// has a link: the place its replies and the app's commands go out.
    private final class Sessions: Sendable {
        private struct Open {
            var clients: Set<Int32> = []
            var links: [Int32: BrowserLink] = [:]
        }
        private let open = Mutex(Open())

        func begin(_ client: Int32, link: BrowserLink) {
            open.withLock {
                $0.clients.insert(client)
                $0.links[client] = link
            }
        }

        func end(_ client: Int32) {
            open.withLock {
                $0.clients.remove(client)
                return $0.links.removeValue(forKey: client)
            }?.end()
            close(client)
        }

        func endAll() {
            for client in open.withLock({ $0.clients }) { shutdown(client, SHUT_RDWR) }
        }

        /// The links whose browser is known and allowed, newest first.
        var commandLinks: [BrowserLink] {
            open.withLock { Array($0.links.values) }.filter(\.isAllowed).sorted { $0.opened > $1.opened }
        }
    }

    /// The browsers connected now, newest first.
    public var connectedBrowsers: [(browser: String, opened: Date)] {
        sessions.commandLinks.compactMap { link in link.browser.map { ($0, link.opened) } }
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
        on listener: Int32, user: uid_t, sessions: Sessions, store: Store, browserOf: @Sendable (Int32) -> String?
    ) {
        while true {
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            guard isPeer(client, user: user), fcntl(client, F_SETFL, 0) == 0 else {
                close(client)
                continue
            }
            let browser = browserOf(client)
            if browser == nil {
                fputs("workbench: a page host connected from a process that is not a browser app\n", stderr)
            }
            let link = BrowserLink(browser: browser, write: { PagesSocket.write(client, $0) })
            sessions.begin(client, link: link)
            Thread.detachNewThread {
                PageHost.serve(
                    read: { PagesSocket.read(client, count: $0) },
                    write: { link.write($0) }, store: store, browser: browser,
                    commands: link)
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

/// A command goes only to a connection whose browser is known and allowed: the newest one.
extension PageHostListener: DriverTransport {
    public func send(_ command: DriverCommand, timeout: TimeInterval) async throws -> DriverReply {
        guard let link = sessions.commandLinks.first else { throw DriverFailure.noBrowserConnected }
        return try await link.send(command, timeout: timeout).get()
    }
}

extension PageHostListener.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .cannotListen: "Workbench could not open the local socket that the browser extension sends to."
        }
    }
}

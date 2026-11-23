import Foundation

/// The native host's whole work: pass each frame the browser sends to the app, and each frame the app sends to the
/// browser. It opens no store and reads no message. When the app does not run, or goes away, it tells the browser with
/// one constant frame, so no page text is kept anywhere while the app is away.
public enum PagesRelay {
    public static let appUnavailable = NativeMessage.frame(Data(#"{"type":"app_unavailable"}"#.utf8))

    private static let reconnectInterval: TimeInterval = 2

    /// Serves one browser session until its input ends. Two pumps run at once, each only framing: the browser's frames
    /// go to the app here, and the app's frames go to the browser from the thread that reads the app's socket. A
    /// frame that cannot be passed on is answered with `appUnavailable`; a broken or oversize frame ends the session.
    public static func run(input: Int32, output: Int32, socketPath: String) {
        let browser = Locked(output)
        let app = AppLink(path: socketPath, browser: browser)
        app.connectInBackground(every: reconnectInterval)
        defer { app.stop() }
        while case .message(let message) = NativeMessage.next(read: { PagesSocket.read(input, count: $0) }) {
            if !app.forward(message) { browser.write(appUnavailable) }
        }
    }
}

/// A descriptor that only one thread writes to at a time, so frames never mix.
private final class Locked: @unchecked Sendable {
    private let lock = NSLock()
    private let descriptor: Int32

    init(_ descriptor: Int32) { self.descriptor = descriptor }

    func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        PagesSocket.write(descriptor, data)
    }
}

/// The connection to the app. The thread that reads it owns the descriptor and closes it.
private final class AppLink: @unchecked Sendable {
    private let lock = NSLock()
    private let path: String
    private let browser: Locked
    private var descriptor: Int32?
    private var stopped = false

    init(path: String, browser: Locked) {
        self.path = path
        self.browser = browser
    }

    /// Whether the app took the frame.
    func forward(_ message: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard connectLocked(), let descriptor else { return false }
        guard PagesSocket.write(descriptor, NativeMessage.frame(message)) else {
            drop(descriptor)
            return false
        }
        return true
    }

    func connectInBackground(every interval: TimeInterval) {
        Thread.detachNewThread { [self] in
            while true {
                lock.lock()
                let done = stopped
                if !done { _ = connectLocked() }
                lock.unlock()
                if done { return }
                Thread.sleep(forTimeInterval: interval)
            }
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        descriptor.map(drop)
    }

    private func connectLocked() -> Bool {
        if descriptor != nil { return true }
        guard !stopped, let connection = PagesSocket.connect(to: path) else { return false }
        descriptor = connection
        Thread.detachNewThread { [self] in pump(connection) }
        return true
    }

    private func drop(_ connection: Int32) {
        descriptor = nil
        shutdown(connection, SHUT_RDWR)
    }

    private func pump(_ connection: Int32) {
        while case .message(let message) = NativeMessage.next(read: { PagesSocket.read(connection, count: $0) }) {
            browser.write(NativeMessage.frame(message))
        }
        lock.lock()
        let lost = descriptor == connection
        if lost { descriptor = nil }
        lock.unlock()
        close(connection)
        if lost { browser.write(PagesRelay.appUnavailable) }
    }
}

import Dispatch
import Foundation
import Synchronization

/// One browser connection, as the app holds it: the place a command goes out and its result comes back. Replies to
/// page messages go out the same way, so every write takes one lock. The browser is known from the process tree.
public final class BrowserLink: Sendable {
    public let browser: String?
    public let opened: Date
    private let writeFrame: @Sendable (Data) -> Bool
    private let writing = Mutex(())
    private let state = Mutex(State())

    private struct State {
        var nextID = 0
        var ended = false
        var waiting: [Int: CheckedContinuation<Result<DriverReply, DriverFailure>, Never>] = [:]
    }

    public init(browser: String?, opened: Date = Date(), write: @escaping @Sendable (Data) -> Bool) {
        self.browser = browser
        self.opened = opened
        self.writeFrame = write
    }

    /// Whether the browser behind the connection is known and is one capture allows.
    var isAllowed: Bool { browser.map(CapturePolicy.browserBundleIDs.contains) ?? false }

    @discardableResult
    public func write(_ frame: Data) -> Bool { writing.withLock { _ in writeFrame(frame) } }

    /// Sends the command and waits for its result, or for the connection to end, or for `timeout` seconds.
    func send(_ command: DriverCommand, timeout: TimeInterval) async -> Result<DriverReply, DriverFailure> {
        await withCheckedContinuation { continuation in
            let id = state.withLock { state -> Int? in
                guard !state.ended else { return nil }
                state.nextID += 1
                state.waiting[state.nextID] = continuation
                return state.nextID
            }
            guard let id else { return continuation.resume(returning: .failure(.connectionLost)) }
            guard write(command.frame(id: id)) else { return resolve(id, .failure(.connectionLost)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in resolve(id, .failure(.timedOut)) }
        }
    }

    /// Takes a message that is a command result and gives it to its waiting command. False for any other message.
    func take(_ message: Data) -> Bool {
        struct Envelope: Decodable { var type: String? }
        guard (try? JSONDecoder().decode(Envelope.self, from: message))?.type == "command_result" else { return false }
        if let reply = try? JSONDecoder().decode(DriverReply.self, from: message), let id = reply.id {
            resolve(id, .success(reply))
        }
        return true
    }

    /// The connection is closed: every waiting command fails, and no later command waits.
    func end() {
        let waiting = state.withLock { state -> [Int: CheckedContinuation<Result<DriverReply, DriverFailure>, Never>] in
            state.ended = true
            defer { state.waiting = [:] }
            return state.waiting
        }
        for continuation in waiting.values { continuation.resume(returning: .failure(.connectionLost)) }
    }

    private func resolve(_ id: Int, _ result: Result<DriverReply, DriverFailure>) {
        state.withLock { $0.waiting.removeValue(forKey: id) }?.resume(returning: result)
    }
}

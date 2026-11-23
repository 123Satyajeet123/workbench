import Foundation

/// What the app asks the browser extension to do. v1 only reads: open a page in a hidden tab, read its text, close
/// every tab the driver opened.
public enum DriverCommand: Sendable, Equatable {
    case open(URL)
    case read(tab: Int)
    case closeAll

    public var name: String {
        switch self {
        case .open: "open"
        case .read: "read"
        case .closeAll: "close_all"
        }
    }

    /// The address or tab the command names, for the log.
    public var target: String? {
        switch self {
        case .open(let url): url.absoluteString
        case .read(let tab): String(tab)
        case .closeAll: nil
        }
    }

    func frame(id: Int) -> Data {
        struct Wire: Encodable {
            var type = "command"
            var id: Int
            var command: String
            var url: String?
            var tab: Int?
        }
        var wire = Wire(id: id, command: name)
        if case .open(let url) = self { wire.url = url.absoluteString }
        if case .read(let tab) = self { wire.tab = tab }
        return NativeMessage.frame((try? JSONEncoder().encode(wire)) ?? Data())
    }
}

/// The extension's answer to one command. `error` is a code from the extension (timeout, incognito, unknown_tab,
/// unreadable, unknown_command, browser_error) when `ok` is false.
public struct DriverReply: Codable, Sendable, Equatable {
    public var id: Int?
    public var ok: Bool
    public var tab: Int?
    public var title: String?
    public var text: String?
    public var closed: Int?
    public var error: String?

    public init(
        id: Int? = nil, ok: Bool, tab: Int? = nil, title: String? = nil, text: String? = nil, closed: Int? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.ok = ok
        self.tab = tab
        self.title = title
        self.text = text
        self.closed = closed
        self.error = error
    }
}

/// Why a page was not read through the browser. Each case is said to the person in plain words.
public enum DriverFailure: Error, Equatable {
    case noBrowserConnected
    case connectionLost
    case timedOut
    case refused(DriverRefusal)
    case capReached(DriverCap)
    case browser(String)
    case couldNotRead
}

public enum DriverCap: Equatable, Sendable {
    case pages(Int)
    case seconds(Int)
}

extension DriverFailure {
    /// The failure came before any page was opened in the browser.
    var browserWasNotUsed: Bool {
        switch self {
        case .noBrowserConnected, .refused, .capReached: true
        case .connectionLost, .timedOut, .browser, .couldNotRead: false
        }
    }
}

extension DriverFailure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noBrowserConnected: "No browser with the Workbench extension is connected, so the page was not opened."
        case .connectionLost: "The browser connection closed before the page was read."
        case .timedOut: "The browser did not answer in time."
        case .refused(let refusal): refusal.description
        case .capReached(.pages(let cap)): "This run opened its limit of \(cap) pages. No more were opened."
        case .capReached(.seconds(let cap)): "This run used its limit of \(cap) seconds. No more pages were opened."
        case .browser(let code): "The browser could not read the page (\(code))."
        case .couldNotRead: "Could not read this page."
        }
    }
}

/// The transport when no browser can be reached: every command fails at once.
public struct NoBrowser: DriverTransport {
    public init() {}

    public func send(_ command: DriverCommand, timeout: TimeInterval) async throws -> DriverReply {
        throw DriverFailure.noBrowserConnected
    }
}

/// Where commands go. The app's listener is the one real transport; tests use a fake.
public protocol DriverTransport: Sendable {
    /// Sends one command to the connected browser and waits for its result. Throws a typed failure; never waits
    /// longer than `timeout` seconds.
    func send(_ command: DriverCommand, timeout: TimeInterval) async throws -> DriverReply
}

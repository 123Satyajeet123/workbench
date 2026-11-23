import Foundation
import Synchronization

@testable import WorkbenchCore

/// A browser that answers from a script. It records every command it was sent.
final class FakeBrowser: DriverTransport, @unchecked Sendable {
    private let state = Mutex(State())

    private struct State {
        var sent: [DriverCommand] = []
        var texts: [String: String] = [:]
        var failure: DriverFailure?
        var openFails: String?
        var tabURLs: [Int: String] = [:]
    }

    var sent: [DriverCommand] { state.withLock { $0.sent } }
    var opens: [URL] { sent.compactMap { if case .open(let url) = $0 { url } else { nil } } }
    var closeAllCount: Int { sent.filter { $0 == .closeAll }.count }

    func serve(_ url: String, text: String) { state.withLock { $0.texts[url] = text } }
    func failEverything(with failure: DriverFailure) { state.withLock { $0.failure = failure } }
    func failOpens(with code: String) { state.withLock { $0.openFails = code } }

    func send(_ command: DriverCommand, timeout: TimeInterval) async throws -> DriverReply {
        try state.withLock { state in
            state.sent.append(command)
            if let failure = state.failure { throw failure }
            switch command {
            case .open(let url):
                if let code = state.openFails { return DriverReply(ok: false, error: code) }
                let tab = state.tabURLs.count + 1
                state.tabURLs[tab] = url.absoluteString
                return DriverReply(ok: true, tab: tab)
            case .read(let tab):
                return DriverReply(ok: true, title: "t", text: state.tabURLs[tab].flatMap { state.texts[$0] } ?? "")
            case .closeAll:
                return DriverReply(ok: true, closed: state.tabURLs.count)
            }
        }
    }
}

final class MemoryDriverLog: DriverLog, @unchecked Sendable {
    private let rows = Mutex<[DriverLogEntry]>([])
    var entries: [DriverLogEntry] { rows.withLock { $0 } }
    func record(_ entry: DriverLogEntry) { rows.withLock { $0.append(entry) } }
}

let webOn = CapturePolicy(switches: [.web: true])

import Foundation

/// The caps of one run. Each is checked before a command leaves the app.
public struct DriverLimits: Sendable, Equatable {
    public var maximumPages = 10
    public var maximumSeconds = 120
    /// The least time between two opens, so the driver does not hit one site in a burst.
    public var minimumGap: Duration = .seconds(2)
    /// How long one command may wait for the browser.
    public var commandTimeout: TimeInterval = 45

    public init() {}
}

/// One row of the trace: a command, the run it belongs to, and how it ended.
public struct DriverLogEntry: Codable, Sendable, Equatable {
    public var runID: String
    public var at: Date
    public var command: String
    public var target: String?
    public var outcome: String
}

public protocol DriverLog: Sendable {
    func record(_ entry: DriverLogEntry)
}

/// Reads one page at a time through the person's browser, inside the gate. Only a run's own opens are counted. The
/// text it returns is data for the reader; nothing here chooses an action from it.
public actor PageDriver {
    private let runID: String
    private let transport: any DriverTransport
    private let gate: DriverGate
    private let limits: DriverLimits
    private let log: any DriverLog
    private let clock: @Sendable () -> Date
    private let pause: @Sendable (Duration) async -> Void
    private let startedAt: Date
    private var opened = 0
    private var lastOpenAt: Date?

    public init(
        runID: String, transport: any DriverTransport, policy: CapturePolicy, limits: DriverLimits = DriverLimits(),
        log: any DriverLog, clock: @escaping @Sendable () -> Date = Date.init,
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.runID = runID
        self.transport = transport
        self.gate = DriverGate(policy: policy)
        self.limits = limits
        self.log = log
        self.clock = clock
        self.pause = pause
        startedAt = clock()
    }

    /// Runs `body` with a driver, and closes every tab the driver opened when `body` ends, with a result or an error.
    public static func run<Result: Sendable>(
        runID: String, transport: any DriverTransport, policy: CapturePolicy, limits: DriverLimits = DriverLimits(),
        log: any DriverLog, clock: @escaping @Sendable () -> Date = Date.init,
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        _ body: (PageDriver) async throws -> Result
    ) async throws -> Result {
        let driver = PageDriver(
            runID: runID, transport: transport, policy: policy, limits: limits, log: log, clock: clock, pause: pause)
        do {
            let result = try await body(driver)
            await driver.finish()
            return result
        } catch {
            await driver.finish()
            throw error
        }
    }

    /// Opens the page in a hidden tab and returns its whole text.
    public func read(_ url: URL) async throws -> FetchedPage {
        let request = DriverRequest(url: url)
        if let refusal = gate.refusal(for: request, at: clock()) {
            record(.open(url), outcome: "refused: \(refusal)")
            throw DriverFailure.refused(refusal)
        }
        try checkCaps(for: .open(url))
        await keepTheGap()
        opened += 1
        lastOpenAt = clock()
        guard let tab = try await send(.open(url)).tab else { throw DriverFailure.browser("no_tab") }
        let reply = try await send(.read(tab: tab))
        return FetchedPage(url: url, text: reply.text ?? "")
    }

    /// Closes every tab this driver opened. Sends nothing when it opened none.
    public func finish() async {
        guard opened > 0 else { return }
        _ = try? await send(.closeAll)
    }

    private func checkCaps(for command: DriverCommand) throws {
        let cap: DriverCap? =
            opened >= limits.maximumPages
            ? .pages(limits.maximumPages)
            : clock().timeIntervalSince(startedAt) >= Double(limits.maximumSeconds)
                ? .seconds(limits.maximumSeconds) : nil
        guard let cap else { return }
        record(command, outcome: "refused: cap \(cap)")
        throw DriverFailure.capReached(cap)
    }

    private func keepTheGap() async {
        guard let lastOpenAt else { return }
        let wait = limits.minimumGap - .seconds(clock().timeIntervalSince(lastOpenAt))
        if wait > .zero { await pause(wait) }
    }

    private func send(_ command: DriverCommand) async throws -> DriverReply {
        do {
            let reply = try await transport.send(command, timeout: limits.commandTimeout)
            guard reply.ok else { throw DriverFailure.browser(reply.error ?? "unknown") }
            record(command, outcome: "ok")
            return reply
        } catch {
            record(command, outcome: "failed: \(error)")
            throw error
        }
    }

    private func record(_ command: DriverCommand, outcome: String) {
        log.record(
            DriverLogEntry(
                runID: runID, at: clock(), command: command.name, target: command.target, outcome: outcome))
    }
}

/// The trace kept in the store, one list of rows for each run.
public struct StoreDriverLog: DriverLog {
    private let store: Store
    private let lock = NSLock()

    public init(store: Store) { self.store = store }

    static func key(_ runID: String) -> String { "driver.run." + runID }

    public func record(_ entry: DriverLogEntry) {
        lock.lock()
        defer { lock.unlock() }
        let key = Self.key(entry.runID)
        let rows = ((try? store.queries.driverLog(runID: entry.runID)) ?? []) + [entry]
        try? store.saveState(Coding.json(rows), forKey: key)
    }
}

extension Queries {
    public func driverLog(runID: String) throws -> [DriverLogEntry] {
        try state(forKey: StoreDriverLog.key(runID)).flatMap { try? Coding.value([DriverLogEntry].self, from: $0) }
            ?? []
    }
}

import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

/// The gate, the caps and the trace of the page driver, with a fake browser. Nothing here opens a real browser.
@Suite struct PageDriverTests {
    private func driver(
        _ browser: FakeBrowser, policy: CapturePolicy = webOn, limits: DriverLimits = DriverLimits(),
        log: MemoryDriverLog = MemoryDriverLog(), clock: @escaping @Sendable () -> Date = { t0 },
        pause: @escaping @Sendable (Duration) async -> Void = { _ in }
    ) -> PageDriver {
        PageDriver(
            runID: "run-1", transport: browser, policy: policy, limits: limits, log: log, clock: clock, pause: pause)
    }

    @Test func aPageAllowedByTheGateIsOpenedAndReadWhole() async throws {
        let browser = FakeBrowser()
        browser.serve("https://news.example.com/a", text: "the whole page")
        let page = try await driver(browser).read(URL(string: "https://news.example.com/a")!)
        #expect(page.text == "the whole page")
        #expect(browser.sent.map(\.name) == ["open", "read"])
    }

    @Test func theGateRefusesBeforeAnyCommandLeavesTheApp() async throws {
        let withDeniedSite = CapturePolicy(switches: [.web: true], denyList: [.web: ["secret.example"]])
        let refused: [(String, CapturePolicy)] = [
            ("ftp://news.example.com/a", webOn), ("javascript:alert(1)", webOn), ("file:///etc/hosts", webOn),
            ("https://user:pw@news.example.com/", webOn), ("http://localhost/admin", webOn),
            ("http://192.168.0.1/", webOn), ("https://router.local/", webOn), ("https://hdfcbank.com/login", webOn),
            ("https://mail.google.com/mail/u/0/", webOn), ("https://web.whatsapp.com/", webOn),
            ("https://www.linkedin.com/in/someone", webOn), ("https://linkedin.com/company/acme", webOn),
            ("https://www.secret.example/a", withDeniedSite), ("https://news.example.com/a", CapturePolicy()),
        ]
        for (address, policy) in refused {
            let browser = FakeBrowser()
            let log = MemoryDriverLog()
            await #expect(throws: DriverFailure.self, "\(address)") {
                try await driver(browser, policy: policy, log: log).read(URL(string: address)!)
            }
            #expect(browser.sent.isEmpty, "\(address) left the app")
            #expect(log.entries.map(\.outcome).allSatisfy { $0.hasPrefix("refused") } && log.entries.count == 1)
        }
    }

    @Test func theGateAllowsAPublicHttpAndHttpsPage() {
        let gate = DriverGate(policy: webOn)
        let allowed = [
            "https://news.example.com/a?b=1", "http://news.example.com/", "https://sub.deep.example.co.uk/",
            "https://notlinkedin.com/",
        ]
        for address in allowed {
            #expect(gate.refusal(for: DriverRequest(url: URL(string: address)!), at: t0) == nil, "\(address)")
        }
    }

    @Test func aRequestThatIsNotAGetIsRefused() {
        let gate = DriverGate(policy: webOn)
        let url = URL(string: "https://news.example.com/a")!
        #expect(gate.refusal(for: DriverRequest(url: url, method: "POST"), at: t0) == .notGET("POST"))
        #expect(gate.refusal(for: DriverRequest(url: url, method: "GET"), at: t0) == nil)
    }

    @Test func theCapOnPagesStopsARun() async throws {
        var limits = DriverLimits()
        limits.maximumPages = 2
        let browser = FakeBrowser()
        let driver = driver(browser, limits: limits)
        for address in ["https://a.example.com/", "https://b.example.com/"] {
            _ = try await driver.read(URL(string: address)!)
        }
        await #expect(throws: DriverFailure.capReached(.pages(2))) {
            try await driver.read(URL(string: "https://c.example.com/")!)
        }
        #expect(browser.opens.count == 2, "the third page never left the app")
    }

    @Test func theCapOnSecondsStopsARun() async throws {
        let now = Mutex(t0)
        var limits = DriverLimits()
        limits.maximumSeconds = 60
        let browser = FakeBrowser()
        let driver = driver(browser, limits: limits, clock: { now.withLock { $0 } })
        _ = try await driver.read(URL(string: "https://a.example.com/")!)
        now.withLock { $0 = t0.addingTimeInterval(59) }
        _ = try await driver.read(URL(string: "https://b.example.com/")!)
        now.withLock { $0 = t0.addingTimeInterval(60) }
        await #expect(throws: DriverFailure.capReached(.seconds(60))) {
            try await driver.read(URL(string: "https://c.example.com/")!)
        }
        #expect(browser.opens.count == 2)
    }

    @Test func twoOpensKeepTheMinimumGap() async throws {
        let now = Mutex(t0)
        let pauses = Mutex<[Duration]>([])
        let browser = FakeBrowser()
        let driver = driver(
            browser, clock: { now.withLock { $0 } },
            pause: { wait in
                pauses.withLock { $0.append(wait) }
                now.withLock { $0 = $0.addingTimeInterval(2) }
            })
        _ = try await driver.read(URL(string: "https://a.example.com/")!)
        now.withLock { $0 = $0.addingTimeInterval(0.5) }
        _ = try await driver.read(URL(string: "https://b.example.com/")!)
        _ = try await driver.read(URL(string: "https://c.example.com/")!)
        #expect(pauses.withLock { $0 } == [.seconds(1.5), .seconds(2)], "the first open waits for nothing")
    }

    @Test func everyCommandHasALogRowWithTheRunId() async throws {
        let browser = FakeBrowser()
        let log = MemoryDriverLog()
        let driver = driver(browser, log: log)
        _ = try await driver.read(URL(string: "https://a.example.com/")!)
        await driver.finish()
        #expect(log.entries.map(\.command) == ["open", "read", "close_all"])
        #expect(log.entries.allSatisfy { $0.runID == "run-1" && $0.outcome == "ok" })
        #expect(log.entries.first?.target == "https://a.example.com/")
        #expect(log.entries.count == browser.sent.count, "no command without a row")
    }

    @Test func aFailedCommandIsLoggedAndTyped() async throws {
        let browser = FakeBrowser()
        browser.failOpens(with: "timeout")
        let log = MemoryDriverLog()
        await #expect(throws: DriverFailure.browser("timeout")) {
            try await driver(browser, log: log).read(URL(string: "https://a.example.com/")!)
        }
        #expect(log.entries.map(\.outcome) == ["failed: browser(\"timeout\")"])
    }

    @Test func everyTabIsClosedWhenTheRunEndsAndWhenItFails() async throws {
        struct Stop: Error {}
        let browser = FakeBrowser()
        let log = MemoryDriverLog()
        let page = try await PageDriver.run(
            runID: "run-2", transport: browser, policy: webOn, log: log
        ) { try await $0.read(URL(string: "https://a.example.com/")!) }
        #expect(page.url.host() == "a.example.com" && browser.closeAllCount == 1)

        await #expect(throws: Stop.self) {
            try await PageDriver.run(runID: "run-3", transport: browser, policy: webOn, log: log) { driver -> Int in
                _ = try await driver.read(URL(string: "https://b.example.com/")!)
                throw Stop()
            }
        }
        #expect(browser.closeAllCount == 2, "the run that failed closed its tabs too")
        #expect(Set(log.entries.map(\.runID)) == ["run-2", "run-3"])
    }

    @Test func aRunThatOpenedNothingSendsNoCloseCommand() async throws {
        let browser = FakeBrowser()
        try await PageDriver.run(runID: "run-4", transport: browser, policy: webOn, log: MemoryDriverLog()) { _ in }
        #expect(browser.sent.isEmpty)
    }

    @Test func theTraceIsKeptInTheStoreByRun() throws {
        let store = try makeStore()
        let log = StoreDriverLog(store: store)
        let entry = DriverLogEntry(
            runID: "run-9", at: t0, command: "open", target: "https://a.example.com/", outcome: "ok")
        log.record(entry)
        log.record(DriverLogEntry(runID: "run-9", at: t0, command: "close_all", target: nil, outcome: "ok"))
        log.record(DriverLogEntry(runID: "run-8", at: t0, command: "close_all", target: nil, outcome: "ok"))
        #expect(try store.queries.driverLog(runID: "run-9").map(\.command) == ["open", "close_all"])
        #expect(try store.queries.driverLog(runID: "run-9").first == entry)
        #expect(try store.queries.driverLog(runID: "run-8").count == 1)
    }
}

import Foundation
import Testing

@testable import WorkbenchCore

/// Probes P0, P2 and P3 of ADR-018 in the founder's own browser. They are skipped unless WORKBENCH_BROWSER_PROBE names
/// one of p0, p2, p3. They listen on the app's socket with a throwaway store, so the Workbench app must not run. The
/// browser must have the extension of this branch loaded. Each probe prints its result and writes it to
/// $WORKBENCH_PROBE_OUT (a folder; default: the temporary folder).
///   WORKBENCH_BROWSER_PROBE=p2 swift test --filter BrowserProbeLiveTests
private enum Live {
    static let chosen = ProcessInfo.processInfo.environment["WORKBENCH_BROWSER_PROBE"]
    static let searchprobe =
        "\(NSHomeDirectory())/Projects/worktrace/research/sources/2026-11-23/browser/searchprobe/results.json"
    static let claims = "\(NSHomeDirectory())/Projects/worktrace/data/vc/dev/claims.json"

    static func environment(_ name: String, default value: String) -> String {
        ProcessInfo.processInfo.environment[name] ?? value
    }

    static func file(_ name: String, default value: String) -> URL { URL(filePath: environment(name, default: value)) }

    /// The app's socket, served by this process, and the first browser that connects to it.
    static func listenForTheBrowser() async throws -> PageHostListener {
        let folder = URL.applicationSupportDirectory.appending(path: "Workbench")
        let path = PagesSocket.path(in: folder)
        if let running = PagesSocket.connect(to: path) {
            close(running)
            throw Failure("the Workbench app is running; quit it first")
        }
        let listener = try PageHostListener(path: path, store: try makeStore(), owner: PageHost.noOwner)
        for _ in 0..<180 where listener.connectedBrowsers.isEmpty { try await Task.sleep(for: .seconds(1)) }
        guard !listener.connectedBrowsers.isEmpty else {
            throw Failure("no browser connected in 3 minutes: reload the extension from Extension/ and try again")
        }
        return listener
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func report(_ name: String, _ lines: [String]) throws {
        print(lines.joined(separator: "\n"))
        let folder = URL(filePath: environment("WORKBENCH_PROBE_OUT", default: NSTemporaryDirectory()))
        try lines.joined(separator: "\n").write(
            to: folder.appending(path: "browser-probe-\(name).txt"), atomically: true, encoding: .utf8)
    }
}

@Suite(.serialized, .enabled(if: Live.chosen != nil, "set WORKBENCH_BROWSER_PROBE to p0, p2 or p3"))
struct BrowserProbeLiveTests {
    /// P0: the service worker stays alive for 10 minutes with an idle port. A harmless command goes every 2 minutes.
    /// Leave the browser alone meanwhile: a page message would restart the worker and hide a death.
    @Test(.enabled(if: Live.chosen == "p0")) func p0TheWorkerStaysAliveWithAnIdlePort() async throws {
        let listener = try await Live.listenForTheBrowser()
        var samples: [DriverProbe.Sample] = []
        for minute in stride(from: 0, through: 10, by: 2) {
            if minute > 0 { try await Task.sleep(for: .seconds(120)) }
            let answered = (try? await listener.send(.closeAll, timeout: 30))?.ok == true
            let opened = listener.connectedBrowsers.first?.opened
            samples.append(DriverProbe.Sample(minute: minute, answered: answered, connectionOpened: opened))
        }
        let alive = DriverProbe.workerStayedAlive(samples)
        try Live.report(
            "p0",
            samples.map {
                "minute \($0.minute): answered \($0.answered), connection opened \($0.connectionOpened.map(\.description) ?? "none")"
            }
                + ["P0 worker stayed alive 10 minutes: \(alive)"])
        #expect(alive)
    }

    /// P2: a tab that is not active, inside a collapsed group, loads the whole page: a lazy page, a script-drawn page,
    /// a static page. Watch the browser: no window or tab may come to the front (that is P1).
    @Test(.enabled(if: Live.chosen == "p2")) func p2AHiddenTabLoadsTheWholePage() async throws {
        let listener = try await Live.listenForTheBrowser()
        var results: [DriverProbe.PageResult] = []
        try await PageDriver.run(
            runID: "probe-p2", transport: listener, policy: webOn, log: MemoryDriverLog()
        ) { driver in
            for page in DriverProbe.p2Pages {
                let outcome: Result<FetchedPage, DriverFailure>
                do { outcome = .success(try await driver.read(page.url)) } catch let failure as DriverFailure {
                    outcome = .failure(failure)
                }
                results.append(DriverProbe.result(of: page, outcome))
            }
        }
        try Live.report(
            "p2",
            results.map {
                "\($0.name): \($0.characters) characters, marker found \($0.markerFound), failure \($0.failure ?? "none")"
            })
        #expect(results.allSatisfy { $0.markerFound })
    }

    /// P3: of the result pages a plain fetch could not read (under 500 characters), how many the browser reads, and
    /// in how many claims the true value then appears. Dev claims only.
    @Test(.enabled(if: Live.chosen == "p3")) func p3TheBrowserReadsWhatTheFetchCouldNot() async throws {
        let decoder = JSONDecoder()
        let results = try decoder.decode(
            [DriverProbe.SearchResult].self,
            from: Data(contentsOf: Live.file("WORKBENCH_PROBE_RESULTS", default: Live.searchprobe)))
        let claims = try decoder.decode(
            [DriverProbe.Claim].self,
            from: Data(contentsOf: Live.file("WORKBENCH_PROBE_CLAIMS", default: Live.claims)))
        let addresses = Array(Set(results.flatMap { $0.results.map(\.url) })).sorted()
        var fetched: [String: String] = [:]
        for address in addresses { fetched[address] = await plainText(of: address) }
        let unreadable = addresses.filter { (fetched[$0] ?? "").count < RoutedPageReader.readableCharacters }

        let listener = try await Live.listenForTheBrowser()
        var limits = DriverLimits()
        limits.maximumPages = unreadable.count
        limits.maximumSeconds = 3_600
        var browsed: [String: String] = [:]
        try await PageDriver.run(
            runID: "probe-p3", transport: listener, policy: webOn, limits: limits, log: MemoryDriverLog()
        ) { driver in
            for address in unreadable {
                browsed[address] = try? await driver.read(URL(string: address)!).text
            }
        }
        let recall = DriverProbe.recall(claims: claims, results: results, fetched: fetched, browsed: browsed)
        try Live.report(
            "p3",
            [
                "dev claims, \(recall.claims) claims, \(recall.pages) result pages",
                "plain fetch under \(RoutedPageReader.readableCharacters) characters: \(recall.plainUnreadable)",
                "browser read \(RoutedPageReader.readableCharacters)+ characters: \(recall.browserReadable)",
                "claims with the true value and the company on a fetched page: \(recall.claimsWithValueFromFetch)",
                "claims with the true value and the company after the browser: \(recall.claimsWithValueAfterBrowser)",
            ])
    }

    private static let browserAgent = "Mozilla/5.0 (Macintosh) AppleWebKit/537.36 Chrome/131 Safari/537.36"

    private func plainText(of address: String) async -> String {
        guard let url = URL(string: address) else { return "" }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Self.browserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession(configuration: .ephemeral).data(for: request) else { return "" }
        return HTMLText.plain(String(decoding: data, as: UTF8.self))
    }
}

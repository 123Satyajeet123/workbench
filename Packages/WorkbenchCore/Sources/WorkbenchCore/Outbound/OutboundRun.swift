import Foundation

public enum OutboundError: Error, Equatable, LocalizedError {
    case nothingToSearch

    public var errorDescription: String? {
        "The criteria have no rule to search for. Add a must or a plus rule, then find startups again."
    }
}

/// One outbound run: the model writes queries for the criteria, the provider searches, https pages are fetched, one
/// model call reads each page into candidates, and code checks and rates them. Every search and fetch goes through the
/// `WebSession`, so consent, the key and the monthly cap are checked before anything is sent.
public struct OutboundRun: Sendable {
    public let session: WebSession
    public let model: RecordedModel
    public let spec: HelperSpec

    public init(session: WebSession, model: RecordedModel, spec: HelperSpec = .outbound) {
        self.session = session
        self.model = model
        self.spec = spec
    }

    public func run() async throws -> OutboundRunRecord {
        let store = session.store
        let started = store.clock()
        guard let criteria = spec.criteria else { throw OutboundError.nothingToSearch }
        let (queries, queryRun) = try await OutboundQueries(model: model).write(for: criteria)
        guard !queries.isEmpty else { throw OutboundError.nothingToSearch }
        let search = try await addresses(for: queries)
        let pages = try await fetched(search.addresses)
        let reading = try await read(pages, fetched: started)
        let known = try store.queries.knownCompanies(task: spec.task)
            .adding(try store.queries.items(of: spec.task, since: WorkDay(containing: started).adding(days: -365)))
        let found = reading.results.flatMap(\.items)
        let fresh = found.filter { !known.contains(name: $0["company"], domain: $0["domain"]) }
        let kept = OutboundReview.bestOfEach(fresh, criteria: criteria, known: known)
        try save(kept, of: reading.results, on: WorkDay(containing: started))
        let runs = [queryRun].compactMap { $0 } + reading.results.compactMap(\.run)
        let record = OutboundRunRecord(
            at: started, queries: queries, pagesRead: reading.read, found: found.count, kept: kept.count,
            alreadyKnown: found.count - fresh.count, stoppedByCap: search.stoppedByCap,
            cost: OutboundCost(
                searches: search.sent, pages: pages.count,
                searchUSD: Double(search.sent) * OutboundCost.searchUSD(try store.queries.webSettings().provider),
                modelUSD: try modelUSD(of: runs, since: started)))
        try store.recordOutboundRun(record, task: spec.task)
        return record
    }

    /// Sends each query while the monthly cap allows. The cap stopping a run is not an error: the pages already found
    /// are still read.
    private func addresses(for queries: [RuleQuery]) async throws -> (
        addresses: [URL], sent: Int, stoppedByCap: Bool
    ) {
        var addresses: [URL] = []
        var sent = 0
        for query in queries {
            do {
                let hits = try await session.search(query.query, count: Outbound.hitsPerQuery)
                sent += 1
                addresses += hits.map(\.url).filter { $0.scheme == "https" && !addresses.contains($0) }
            } catch WebBlock.capReached {
                return (addresses, sent, true)
            } catch let block as WebBlock {
                throw block
            } catch {
                sent += 1
            }
        }
        return (addresses, sent, false)
    }

    private func fetched(_ addresses: [URL]) async throws -> [FetchedPage] {
        var pages: [FetchedPage] = []
        for address in addresses.prefix(Outbound.maxPages) {
            do {
                pages.append(try await session.fetch(address))
            } catch let block as WebBlock {
                throw block
            } catch {
                continue
            }
        }
        return pages.filter { $0.text.cleaned != nil }
    }

    /// One model call for each page. A page the model's reply could not be read for is left out and counted.
    private func read(_ pages: [FetchedPage], fetched: Date) async throws -> (
        results: [HelperReader.Result], read: Int
    ) {
        var results: [HelperReader.Result] = []
        for page in pages {
            do {
                results.append(try await OutboundReader(model: model, spec: spec).read(page, fetched: fetched))
            } catch is StructuredModelError {
                continue
            }
        }
        return (results, results.count)
    }

    private func save(_ kept: [Item], of results: [HelperReader.Result], on day: WorkDay) throws {
        let keys = Set(kept.map(Self.key))
        for result in results {
            let own = result.items.filter { keys.contains(Self.key($0)) }
            guard !own.isEmpty || result.run != nil else { continue }
            try session.store.saveReading(
                HelperReader.Result(
                    items: own, dropped: result.dropped + result.items.count - own.count, run: result.run),
                of: spec, day: day, scope: "", grant: session.grant)
        }
    }

    private static func key(_ item: Item) -> String { item[Outbound.urlField] + "|" + item["company"].comparable }

    private func modelUSD(of runs: [RunID], since start: Date) throws -> Double {
        try session.store.queries.runs(since: start).filter { runs.contains($0.id) }.reduce(0) { $0 + $1.usage.costUSD }
    }
}

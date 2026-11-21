import Foundation

/// Reads one fetched page into candidate startups with one model call, through the helper reader. The model lists the
/// startups and judges each rule. Code keeps a candidate only when its quote is in the page (the reader checks it), its
/// name is in the page as whole words, and drops a domain the page does not write. A rule whose quote is not in the
/// page reads unknown.
public struct OutboundReader: Sendable {
    public let model: RecordedModel
    public let spec: HelperSpec

    public init(model: RecordedModel, spec: HelperSpec = .outbound) {
        self.model = model
        self.spec = spec
    }

    /// A page is read alone, so its one line is always number 1.
    public func read(_ page: FetchedPage, fetched: Date) async throws -> HelperReader.Result {
        let text = String(page.text.prefix(Outbound.pageBudget))
        let line = Evidence(
            id: Outbound.pageLine, start: fetched, line: "\(page.url.absoluteString) — \(text)", quotable: [text])
        let read = try await HelperReader(spec: spec, model: model).read(
            day: WorkDay(containing: fetched), scope: "", evidence: EvidenceSet(lines: [line]))
        let words = CompanyName.words(text)
        var kept: [Item] = []
        for item in read.items {
            let name = CompanyName.normal(item["company"])
            guard !name.isEmpty, CompanyName.contains(words, term: name),
                !kept.contains(where: { CompanyName.normal($0["company"]) == name })
            else { continue }
            kept.append(Self.candidate(item, page: page, text: text, fetched: fetched))
        }
        return HelperReader.Result(items: kept, dropped: read.items.count - kept.count + read.dropped, run: read.run)
    }

    private static func candidate(_ item: Item, page: FetchedPage, text: String, fetched: Date) -> Item {
        var candidate = item
        let domain = CompanyName.domain(item["domain"]).flatMap { CompanyName.mentions(text, domain: $0) ? $0 : nil }
        candidate.fields["domain"] = domain ?? ""
        candidate.fields[Outbound.urlField] = page.url.absoluteString
        candidate.fields[Outbound.fetchedField] = WorkDay(containing: fetched).description
        return candidate
    }
}

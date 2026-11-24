import Foundation

/// Turns one article into typed facts with one model call, through the helper reader. The model chooses the event,
/// the polarity, the date and the company among the candidates. Code keeps a fact only when the company is a candidate
/// (the reader checks it), the quote is in the article and has at most 25 words, and the date is a real day: any
/// other date becomes the day the article came out.
public struct SignalReader: Sendable {
    public let model: RecordedModel
    public let spec: HelperSpec

    public init(model: RecordedModel, spec: HelperSpec = .newsSignals) {
        self.model = model
        self.spec = spec
    }

    public func read(_ article: NewsArticle, candidates: [Candidate]) async throws -> HelperReader.Result {
        let text = String(article.text.prefix(NewsSignals.articleBudget))
        let line = Evidence(
            id: article.id, start: article.published, line: "\(article.feed) — \(article.title): \(text)",
            quotable: [text, article.title])
        let evidence = EvidenceSet(lines: [line], context: [NewsSignals.companies: candidates.map(\.label)])
        let day = WorkDay(containing: article.published)
        let read = try await HelperReader(spec: spec, model: model).read(
            day: day, scope: "", evidence: evidence)
        var kept: [Item] = []
        for item in read.items {
            guard let company = candidates.first(where: { $0.label == item["company"] })?.company,
                item.quote.split(whereSeparator: \.isWhitespace).count <= NewsSignals.quoteWords
            else { continue }
            let fact = self.fact(item, about: company, in: article)
            if !kept.contains(where: { $0.fields == fact.fields && $0.quote == fact.quote }) { kept.append(fact) }
        }
        return HelperReader.Result(items: kept, dropped: read.items.count - kept.count + read.dropped, run: read.run)
    }

    private func fact(_ item: Item, about company: WatchedCompany, in article: NewsArticle) -> Item {
        var fact = item
        fact.fields["company"] = company.name
        fact.fields["date"] = WorkDay(item["date"])?.description ?? WorkDay(containing: article.published).description
        fact.fields[NewsSignals.idField] = company.id
        fact.fields[NewsSignals.urlField] = article.url.absoluteString
        fact.fields[NewsSignals.feedField] = article.feed
        fact.fields[NewsSignals.trustedField] =
            spec.trusts(feed: article.feed) ? NewsSignals.trusted : NewsSignals.untrusted
        fact.fields[NewsSignals.headlineField] = article.title
        return fact
    }
}

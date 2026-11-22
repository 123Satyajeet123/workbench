import Foundation

public struct AgreementReader: Sendable {
    private let reader: HelperReader

    public init(spec: HelperSpec, model: RecordedModel) {
        reader = HelperReader(spec: spec, model: model)
    }

    public func read(_ deal: PastDeal, on day: WorkDay) async throws -> PastDeal {
        let line = Evidence(id: 1, start: day.start, line: "\(deal.company): \(deal.text)", quotable: [deal.text])
        let result = try await reader.read(
            day: day, scope: "agreement", evidence: EvidenceSet(lines: [line]))
        var read = deal
        read.reading = result.items.first?.fields ?? reader.spec.criteria?.unanswered ?? [:]
        return read
    }
}

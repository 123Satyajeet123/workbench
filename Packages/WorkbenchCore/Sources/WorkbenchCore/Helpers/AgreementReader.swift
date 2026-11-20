import Foundation

/// Reads a past deal's pasted text with the machine's own reader, so the criteria are judged exactly as a live deal is.
/// The reading is kept on the deal and never saved as an item or a mark.
public struct AgreementReader: Sendable {
    private let reader: HelperReader

    public init(spec: HelperSpec, model: RecordedModel) {
        reader = HelperReader(spec: spec, model: model)
    }

    /// The deal with the readings of its first item. When the model found no deal in the text, every rule is
    /// read and unknown, so the investor sees the gap instead of a guess.
    public func read(_ deal: PastDeal, on day: WorkDay) async throws -> PastDeal {
        let line = Evidence(id: 1, start: day.start, line: "\(deal.company): \(deal.text)", quotable: [deal.text])
        let result = try await reader.read(
            day: day, scope: "agreement", evidence: EvidenceSet(lines: [line]))
        var read = deal
        read.reading = result.items.first?.fields ?? reader.spec.criteria?.unanswered ?? [:]
        return read
    }
}

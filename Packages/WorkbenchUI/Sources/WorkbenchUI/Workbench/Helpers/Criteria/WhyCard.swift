import SwiftUI
import WorkbenchCore

struct WhyCard: View {
    let triage: Triage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(triage.rating.rawValue.capitalized).textStyle(.headline)
                    .foregroundStyle(triage.rating.tone.color)
                Text(decision).textStyle(.callout).foregroundStyle(.supporting)
            }
            if triage.needsReview { ReviewFlag(reasons: triage.review) }
            ForEach(triage.results) { RuleResultRow(result: $0, isDeciding: triage.decidedBy.contains($0.id)) }
        }
        .calloutBox(fillsWidth: true)
    }

    private var decision: String {
        let names = triage.results.filter { triage.decidedBy.contains($0.id) }.map(\.rule.summary)
        return names.isEmpty ? "No rule pushed it either way." : "Decided by: \(names.joined(separator: "; "))"
    }
}

struct WhyDisclosure: View {
    let triage: Triage
    let isOpen: Bool

    init(triage: Triage, isOpen: Bool = false) {
        self.triage = triage
        self.isOpen = isOpen
    }

    var body: some View {
        Fold(isOpen: isOpen) {
            WhyCard(triage: triage).padding(.top, Space.xs)
        } label: {
            Text("Why \(triage.rating.rawValue)" + (triage.needsReview ? " · needs your review" : ""))
                .foregroundStyle(triage.needsReview ? Tone.attention.color : Color.secondary)
        }
        .textStyle(.callout)
    }
}

private struct ReviewFlag: View {
    let reasons: [String]

    var body: some View {
        Label("Needs your review: \(reasons.joined(separator: " "))", systemImage: "eye")
            .textStyle(.callout).foregroundStyle(Tone.attention.color)
    }
}

private struct RuleResultRow: View {
    let result: RuleResult
    let isDeciding: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: result.verdict.symbol).foregroundStyle(result.verdict.tone.color)
                .zoomedWidth(18).accessibilityLabel(result.verdict.rawValue)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.rule.summary) · \(result.rule.role.words)")
                    .fontWeight(isDeciding ? .semibold : .regular)
                if let found = found { Text(found).textStyle(.callout) }
                if let reason = result.reason { Text(reason).textStyle(.callout).foregroundStyle(.supporting) }
                if let quote = result.quote?.cleaned {
                    Text("“\(quote)”").textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                }
            }
        }
    }

    private var found: String? {
        guard case .number(let test) = result.rule.test else { return nil }
        if let number = result.number { return "Found \(number.shown) \(test.unit)" }
        return result.isRead ? "No number in the text: unknown, not a fail." : "Not read under this rule yet."
    }
}

extension Verdict {
    var symbol: String {
        switch self {
        case .pass: "checkmark.circle.fill"
        case .fail: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var tone: Tone {
        switch self {
        case .pass: .good
        case .fail: .bad
        case .unknown: .attention
        }
    }
}

extension Rating {
    var tone: Tone {
        switch self {
        case .hot: .good
        case .warm: .neutral
        case .cold: .bad
        }
    }
}

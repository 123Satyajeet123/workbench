import SwiftUI
import WorkbenchCore

extension ClaimVerdict {
    /// "No public evidence" is grey, never red: most true claims of a private startup have no page.
    var tone: Tone {
        switch self {
        case .supported: .good
        case .contradicted: .bad
        case .notFound: .neutral
        case .unclear: .attention
        }
    }
}

/// A deal's claims, under the why card: pick the claims to check, then each verdict with the words and the link it
/// rests on, and two marks: is the quote right, is the verdict right.
struct ClaimChecksSection: View {
    let deal: WorkObject
    @Environment(ClaimsModel.self) private var claims

    private var state: ClaimsModel.DealClaims { claims.state(of: deal) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text("Claims").textStyle(.headline)
                Spacer()
                Button(claims.busy.contains(deal.id) ? "Working…" : "Read claims from the deck") {
                    Task { await claims.extract(from: deal) }
                }
                .disabled(claims.busy.contains(deal.id))
            }
            if let problem = claims.problems.text { ProblemBanner(text: problem, dismiss: claims.problems.dismiss) }
            if state.claims.isEmpty {
                Text("No claims yet. Read them from the deck, then choose which to check.").textStyle(.callout)
                    .foregroundStyle(.supporting)
            }
            ForEach(state.claims) { claim in ClaimRow(deal: deal, claim: claim) }
            if !state.chosen.isEmpty {
                Button("Check \(state.chosen.count) chosen on the web") { Task { await claims.checkChosen(in: deal) } }
                    .disabled(claims.busy.contains(deal.id))
                Text("Sends search queries about these claims to your search provider. See Settings › Capture.")
                    .textStyle(.callout).foregroundStyle(.supporting)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
        .onAppear { claims.refresh(deal) }
    }
}

private struct ClaimRow: View {
    let deal: WorkObject
    let claim: Claim
    @Environment(ClaimsModel.self) private var claims

    var body: some View {
        let state = claims.state(of: deal)
        VStack(alignment: .leading, spacing: Space.xs) {
            Toggle(
                isOn: Binding(
                    get: { claim.id.map(state.chosen.contains) ?? false }, set: { _ in claims.toggle(claim, in: deal) })
            ) {
                Text(claim.text)
            }
            Text("\(claim.type.rawValue.replacingOccurrences(of: "_", with: " ")) · “\(claim.quote)”")
                .textStyle(.callout).foregroundStyle(.supporting)
            if let check = state.check(of: claim) { VerdictView(deal: deal, check: check) }
        }
    }
}

private struct VerdictView: View {
    let deal: WorkObject
    let check: ClaimCheck
    @Environment(ClaimsModel.self) private var claims

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(check.verdict.title).textStyle(.headline).foregroundStyle(check.verdict.tone.color)
            if !check.quote.isEmpty {
                Text("“\(check.quote)”").textSelection(.enabled)
                if let link = URL(string: check.url) { Link(link.host() ?? check.url, destination: link) }
                markRow("Quote", mark: check.quoteMark) { claims.markQuote(check, as: $0, in: deal) }
            } else {
                Text(
                    check.verdict == .notFound
                        ? "No page said anything about it. That is not a sign it is false."
                        : "The pages did not settle it."
                )
                .textStyle(.callout).foregroundStyle(.supporting)
            }
            markRow("Verdict", mark: check.verdictMark) { claims.markVerdict(check, as: $0, in: deal) }
        }
        .padding(.leading, Space.m)
    }

    private func markRow(_ name: String, mark: Mark, set: @escaping (Mark) -> Void) -> some View {
        HStack(spacing: Space.s) {
            Text("\(name) right?").textStyle(.callout).foregroundStyle(.supporting)
            Button("Right") { set(.confirmed) }.disabled(mark == .confirmed)
            Button("Wrong") { set(.rejected) }.disabled(mark == .rejected)
        }
        .buttonStyle(.borderless)
    }
}

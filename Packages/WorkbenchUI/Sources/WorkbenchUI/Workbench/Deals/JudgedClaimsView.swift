import SwiftUI
import WorkbenchCore

extension Verdict {
    var word: String {
        switch self {
        case .pass: "pass"
        case .fail: "fail"
        case .unknown: "unknown"
        }
    }
}

/// The claims the judge looked at, with what each stage decided and a place to mark each one: right, wrong, or
/// unsupported. A catch claim is shown like any other. Unknown is never shown as a pass.
struct JudgedClaimsView: View {
    let deal: WorkObject
    @Environment(ClaimsModel.self) private var claims

    private var judged: [JudgedClaim] { claims.state(of: deal).judged }

    var body: some View {
        if !judged.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Judged claims").textStyle(.headline)
                if let rung = claims.state(of: deal).rung { RungLine(report: rung) }
                AgreementLine(agreement: claims.state(of: deal).agreement)
                ForEach(judged) { claim in
                    JudgedClaimRow(claim: claim) { claims.mark(claim, as: $0, in: deal) }
                }
            }
        }
    }
}

private struct JudgedClaimRow: View {
    let claim: JudgedClaim
    let mark: (ClaimMark) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(claim.text).textStyle(.body)
            if let structure = claim.structure { stage("Structure", structure) }
            if let grounding = claim.grounding { stage("Grounding", grounding) }
            HStack(spacing: Space.s) {
                ForEach(ClaimMark.allCases, id: \.self) { choice in
                    Button(choice.title) { mark(choice) }.buttonStyle(.ghost).disabled(claim.mark != .proposed)
                }
                if claim.mark != .proposed { Text("Marked").textStyle(.callout).foregroundStyle(.supporting) }
            }
        }
        .padding(Space.s)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }

    private func stage(_ name: String, _ verdict: StageVerdict) -> some View {
        HStack(spacing: Space.s) {
            Chip("\(name): \(verdict.verdict.word)", tone: verdict.verdict.tone)
            Text(verdict.plainWords).textStyle(.callout).foregroundStyle(.supporting)
        }
    }
}

private struct RungLine: View {
    let report: RungReport

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs / 2) {
            Text("What the agent may do: \(report.computed.title)").textStyle(.callout)
            Text(report.plainWords).textStyle(.callout).foregroundStyle(.supporting)
        }
    }
}

private struct AgreementLine: View {
    let agreement: JudgeAgreement

    var body: some View {
        Text(agreement.plainWords).textStyle(.callout).foregroundStyle(.supporting)
    }
}

extension ClaimMark {
    var title: String {
        switch self {
        case .right: "Right"
        case .wrong: "Wrong"
        case .unsupported: "Unsupported"
        }
    }
}

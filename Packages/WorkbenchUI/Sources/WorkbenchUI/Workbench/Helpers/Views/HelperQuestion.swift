import SwiftUI
import WorkbenchCore

/// An item the app picked from the last reading. Answering it measures the helper without your choice of what to
/// check.
struct HelperQuestion: View {
    let model: HelperModel
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("\(model.name) asks: is this right?", systemImage: "questionmark.bubble").textStyle(.headline)
            ItemRow(model: model, item: item, showsSpan: model.spec.citation == .range)
            Text(
                "Picked at random: every new item has a \(RunSettings.standard.pickChance.formatted(.percent)) chance of being asked, so your answer shows how often \(model.name) is right."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            if let trust = model.trust { TrustLine(name: model.name, status: trust) }
        }
        .padding(Space.m)
        .background(Tone.attention.color.opacity(0.08), in: .rect(cornerRadius: Radius.card))
    }
}

/// The words for a certificate that the method does not yet back fully: it counts per run, not per fact, and a check
/// the person skipped does not count against the machine (sims-D6 P3, P4). Until the draw ledger lands, "earned" says so.
enum TrustWording {
    static let earned = "trusted (provisional)"
    /// The one claim the test backs (sims-D6-itemlevel-proofcheck): a tighter bound would need its own proof.
    static let claim = "at most 10% of its facts are wrong, 90% sure"
    static let limit = "Provisional: counted per run, and checks you skipped are not counted yet."
}

/// Progress toward trust: a betting test on audit answers on held-out days, valid however often it is read.
struct TrustLine: View {
    let name: String
    let status: Certificate.Status

    var body: some View {
        switch status {
        case .earned:
            Label(
                "\(name) is \(TrustWording.earned): \(TrustWording.claim). \(TrustWording.limit)",
                systemImage: "checkmark.shield"
            )
            .foregroundStyle(Tone.good.color).textStyle(.callout)
        case .needsMore(let more):
            Text(
                "\(name) earns trust at most 10% wrong, 90% sure. It needs at least \(more) more checked runs with every checked item right, on the days set aside for testing."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
        }
    }
}

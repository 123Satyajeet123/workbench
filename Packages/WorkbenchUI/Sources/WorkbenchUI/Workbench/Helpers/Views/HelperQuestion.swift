import SwiftUI
import WorkbenchCore

/// The one item the app picked from the last reading. Answering it measures the helper without your choice of what
/// to check.
struct HelperQuestion: View {
    let model: HelperModel
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("\(model.name) asks: is this right?", systemImage: "questionmark.bubble").textStyle(.headline)
            ItemRow(model: model, item: item, showsSpan: model.spec.citation == .range)
            Text("Picked at random from this reading, so your answer shows how often \(model.name) is right.")
                .textStyle(.callout).foregroundStyle(.supporting)
            if let trust = model.trust { TrustLine(name: model.name, status: trust) }
        }
        .padding(Space.m)
        .background(Tone.attention.color.opacity(0.08), in: .rect(cornerRadius: Radius.card))
    }
}

/// Progress toward trust: the exact binomial bound from audit answers on held-out days.
struct TrustLine: View {
    let name: String
    let status: Certificate.Status

    var body: some View {
        switch status {
        case .earned(let bound):
            Label(
                "\(name) has earned trust: wrong at most \(bound.formatted(.percent.precision(.fractionLength(1)))) of the time, 90% sure.",
                systemImage: "checkmark.shield"
            )
            .foregroundStyle(Tone.good.color).textStyle(.callout)
        case .needsMore(let more):
            Text(
                "\(name) earns trust at most 10% wrong, 90% sure. It needs at least \(more) more right answers on held-out days."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
        }
    }
}

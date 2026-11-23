import SwiftUI
import WorkbenchCore

/// One startup found on the web: its name, class and the page it was found on, the why card with the rule, the number
/// and the quote, and the three things the investor does with it. Each choice is the investor's click.
struct CandidateCard: View {
    let candidate: OutboundCandidate
    var showsWhy = false
    let addToDeals: () -> Void
    let notAFit: (String) -> Void
    let snooze: (Int) -> Void
    @State private var isAsking = false
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(candidate.company).textStyle(.headline)
                Text(candidate.triage.rating.rawValue).textStyle(.caption)
                    .padding(.horizontal, Space.s).padding(.vertical, 2)
                    .background(candidate.triage.rating.tone.color.opacity(0.2), in: .capsule)
                if let sector = candidate.sector { Text(sector).textStyle(.callout).foregroundStyle(.supporting) }
                Spacer()
                actions
            }
            source
            Text("“\(candidate.item.quote)”").textStyle(.callout).foregroundStyle(.supporting)
                .textSelection(.enabled)
            WhyDisclosure(triage: candidate.triage, isOpen: showsWhy)
        }
        .padding(Space.m)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: Radius.card))
    }

    @ViewBuilder private var source: some View {
        if let url = candidate.url {
            HStack(spacing: Space.s) {
                if let domain = candidate.domain { Text(domain).textStyle(.caption) }
                Link("Found on \(url.host() ?? url.absoluteString)", destination: url).textStyle(.caption)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Space.s) {
            Button("Add to Deals", action: addToDeals).buttonStyle(.borderedProminent)
            Button("Not a fit") { isAsking = true }
                .popover(isPresented: $isAsking) { reasonForm }
            Menu("Snooze") {
                Button("3 days") { snooze(3) }
                Button("1 week") { snooze(7) }
                Button("1 month") { snooze(30) }
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .controlSize(.small)
    }

    private var reasonForm: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Why is it not a fit? (optional)").textStyle(.headline)
            TextField("For example: too late stage", text: $reason).zoomedWidth(260)
            Text("Kept for when you edit the criteria. Nothing applies it by itself.").textStyle(.caption)
                .foregroundStyle(.supporting)
            HStack {
                Spacer()
                Button("Not a fit") {
                    isAsking = false
                    notAFit(reason)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.m)
    }
}

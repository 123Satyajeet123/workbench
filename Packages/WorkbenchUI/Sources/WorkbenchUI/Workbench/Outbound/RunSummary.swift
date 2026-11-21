import SwiftUI
import WorkbenchCore

/// What the last run sent and cost, the queries it used, and what the next run is expected to cost. Searches are priced
/// at the provider's list price; model calls at the model's list price, which on a subscription is not billed.
struct RunSummary: View {
    let last: OutboundRunRecord?
    let next: OutboundCost
    let sentThisMonth: Int
    let cap: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let last {
                Text("Last run, \(last.at.formatted(date: .abbreviated, time: .shortened))").textStyle(.headline)
                Text(counts(last)).textStyle(.callout)
                Text(cost(last.cost)).textStyle(.callout)
                if last.stoppedByCap {
                    Label("The monthly cap stopped the searches.", systemImage: "hand.raised")
                        .textStyle(.callout).foregroundStyle(Tone.attention.color)
                }
                queries(last)
            }
            Text(
                "Next run: about \(next.searches) searches and up to \(next.pages) pages, about \(money(next.totalUSD)). \(sentThisMonth) of \(cap) searches sent this month."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
        }
    }

    private func counts(_ run: OutboundRunRecord) -> String {
        "\(run.cost.searches) searches, \(run.pagesRead) pages read, \(run.found) startups found, \(run.kept) new, \(run.alreadyKnown) already in Deals or turned down."
    }

    private func cost(_ cost: OutboundCost) -> String {
        "Cost about \(money(cost.totalUSD)): searches \(money(cost.searchUSD)), model calls \(money(cost.modelUSD)) at list price."
    }

    private func queries(_ run: OutboundRunRecord) -> some View {
        DisclosureGroup("Queries sent (\(run.queries.count))") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(run.queries.enumerated()), id: \.offset) { _, query in
                    Text(query.query).textStyle(.callout).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Space.xs)
        }
        .textStyle(.callout)
    }

    private func money(_ dollars: Double) -> String {
        dollars.formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

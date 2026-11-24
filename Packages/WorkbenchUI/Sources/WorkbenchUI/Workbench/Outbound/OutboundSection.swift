import SwiftUI
import WorkbenchCore

/// The outbound machine's page: where its criteria came from, what the last run cost, and the review list: startups
/// ranked by class, then points, each with its why card and the three things to do with it.
struct OutboundSection: View {
    let model: HelperModel
    let source: OutboundSource
    var showsWhy = false
    @Environment(Crew.self) private var crew
    @Environment(DealsModel.self) private var deals
    @Environment(WebResearchSettings.self) private var web

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(criteriaNote).textStyle(.callout).foregroundStyle(.supporting)
            RunSummary(
                last: source.runs.last,
                next: .nextRun(criteria: criteria, provider: web.provider, last: source.runs.last?.cost),
                sentThisMonth: web.queriesThisMonth, cap: web.monthlyCap)
            if candidates.isEmpty {
                Text("No startups to review. Press Find startups to search the web for ones that fit your criteria.")
                    .foregroundStyle(.supporting)
            }
            ForEach(candidates) { candidate in
                CandidateCard(
                    candidate: candidate, showsWhy: showsWhy,
                    addToDeals: { Task { await add(candidate) } }, notAFit: { act(on: candidate, notAFit: $0) },
                    snooze: { act(on: candidate, snooze: $0) })
            }
        }
    }

    private var criteria: Criteria { model.spec.criteria ?? Criteria() }

    /// The review list: ranked by the criteria as they are now.
    private var candidates: [OutboundCandidate] {
        OutboundReview.list(source.items, criteria: criteria, known: source.known, now: .now)
    }

    /// Whether the criteria still match those of the machine that rates in the same folder, so an edit on one page does
    /// not surprise the other.
    private var criteriaNote: String {
        guard let source = crew.thesisSource(for: model), let thesis = source.spec.criteria else {
            return "Criteria version \(criteria.version)."
        }
        return thesis == criteria
            ? "Criteria: a copy of \(source.name)'s, still the same (version \(criteria.version))."
            : "Criteria: copied from \(source.name), now edited here (version \(criteria.version)). \(source.name) keeps its own."
    }

    private func add(_ candidate: OutboundCandidate) async {
        await deals.addCandidate(candidate.item, of: model, from: source)
        changed()
    }

    private func act(on candidate: OutboundCandidate, notAFit reason: String) {
        model.attempt("save your answer") { try source.notAFit(candidate.item, reason: reason) }
        changed()
    }

    private func act(on candidate: OutboundCandidate, snooze days: Int) {
        model.attempt("snooze the startup") { try source.snooze(candidate.item, days: days) }
        changed()
    }

    private func changed() {
        model.reload()
        model.itemsChanged()
    }
}

extension OutboundSource {
    func chooser(for model: HelperModel) -> AnyView? { AnyView(OutboundChooser(model: model)) }
    func itemsView(for model: HelperModel) -> AnyView? { AnyView(OutboundSection(model: model, source: self)) }
}

/// What the outbound machine needs before it can search: the web research switch and a key, in plain words.
struct OutboundChooser: View {
    let model: HelperModel
    @Environment(CaptureSettings.self) private var capture
    @Environment(WebResearchSettings.self) private var web

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "\(model.name) writes search queries from your criteria, sends them to \(web.provider.title), and fetches the pages that come back. The queries are words about what you look for; they name none of your deals and nothing about you. Fetched pages are kept 30 days and deleted with the rest of your web data. It is off until you switch on web research and save a key in Settings."
            )
            .foregroundStyle(.supporting)
            Button("Turn on web research") {
                capture.set(.web, on: true)
                model.reload()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// The weekly search switch, in the machine's settings.
struct WeeklySearchRow: View {
    let model: HelperModel

    var body: some View {
        Toggle(
            "Find startups every week while Workbench is open",
            isOn: Binding(get: { model.weekly.isOn }, set: { model.weekly.isOn = $0 })
        )
        .toggleStyle(.switch)
    }
}

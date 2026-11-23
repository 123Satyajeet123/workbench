import SwiftUI
import UniformTypeIdentifiers
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

/// What a deal holds that can be checked, over its evidence from any source: the rating against the team's thesis and
/// the claims. Each fact is one row; the one question of a row is right or wrong. A file dropped on the section is added
/// to the deal.
struct ClaimChecksSection: View {
    let deal: WorkObject
    @Environment(ClaimsModel.self) private var claims
    @Environment(Crew.self) private var crew
    @State private var selected: Int64?
    @State private var hovered: Int64?
    @State private var typed = ""
    @State private var isChoosingFile = false
    @State private var proof: ProofModel?

    private var state: ClaimsModel.DealClaims { claims.state(of: deal) }
    private var isBusy: Bool { claims.busy.contains(deal.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Claims").textStyle(.headline)
            if let problem = claims.problems.text { ProblemBanner(text: problem, dismiss: claims.problems.dismiss) }
            if let rating = state.rating, let triage = state.triage {
                row(rating, title: "Rated \(triage.rating.rawValue)", shown: rating.shownAsRating(triage))
            }
            ForEach(state.claims) { claim in
                if let item = claim.id.flatMap({ state.items[$0] }) {
                    HStack(spacing: Space.s) {
                        Toggle(
                            "Check on the web",
                            isOn: Binding(
                                get: { claim.id.map(state.chosen.contains) ?? false },
                                set: { _ in claims.toggle(claim, in: deal) })
                        )
                        .labelsHidden().toggleStyle(.checkbox)
                        row(item, title: claim.text, shown: item)
                    }
                    if let check = state.check(of: claim), let verdict = check.id.flatMap({ state.items[$0] }) {
                        row(verdict, title: claim.text, shown: verdict.shownAsVerdict(check))
                            .padding(.leading, Space.l)
                    }
                }
            }
            if state.claims.isEmpty && state.rating == nil {
                Text("Nothing yet. Add a file, type a claim, or read the claims in what is linked.")
                    .textStyle(.callout).foregroundStyle(.supporting)
            }
            JudgedClaimsView(deal: deal)
            if let selected, let item = state.items[selected], let proof {
                InspectorView(item: item) { EmptyView() }.environment(proof).frame(maxWidth: .infinity)
            }
            actions
        }
        .calloutBox(fillsWidth: true)
        .onAppear {
            claims.refresh(deal)
            proof = claims.proofModel(crew: crew)
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { claims.addFile(url, to: deal) }
            return !urls.isEmpty
        }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.pdf, .image]) { result in
            if case .success(let url) = result { claims.addFile(url, to: deal) }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button("Add a file") { isChoosingFile = true }
            TextField("Add a claim", text: $typed, prompt: Text("Type a claim, then press Return"))
                .onSubmit {
                    claims.addClaim(typed, to: deal)
                    typed = ""
                }
            Button(isBusy ? "Working…" : "Read the claims") { Task { await claims.extract(from: deal) } }
            Button(isBusy ? "Working…" : "Rate against our thesis") { Task { await claims.rate(deal) } }
            if !state.chosen.isEmpty {
                Button("Check \(state.chosen.count) chosen on the web") { Task { await claims.checkChosen(in: deal) } }
                Text("Sends search queries about these claims to your search provider. See Settings › Capture.")
                    .textStyle(.callout).foregroundStyle(.supporting)
            }
        }
        .disabled(isBusy)
        .buttonStyle(.ghost)
    }

    @ViewBuilder private func row(_ item: Item, title: String, shown: Item) -> some View {
        if let row = FactRow(item: shown, title: title), let id = item.id {
            FactCard(
                row: row, offered: FactAction.offered(for: item, isOpenFact: false), isSelected: selected == id,
                isHovered: hovered == id,
                hover: { inside in hovered = inside ? id : (hovered == id ? nil : hovered) },
                open: { selected = selected == id ? nil : id },
                act: { action in claims.mark(item, as: action == .right ? .confirmed : .rejected, in: deal) })
        }
    }
}

extension Item {
    /// The rating fact as a row shows it: the call first, then the words it rests on.
    fileprivate func shownAsRating(_ triage: Triage) -> Item {
        var shown = self
        shown.fields["person"] = triage.rating.rawValue.capitalized
        return shown
    }

    /// A verdict as a row shows it: the verdict first, then the page's words, and the page's site.
    fileprivate func shownAsVerdict(_ check: ClaimCheck) -> Item {
        var shown = self
        shown.fields["person"] = check.verdict.title
        shown.fields["project"] = URL(string: check.url)?.host() ?? ""
        shown.quote = check.quote
        return shown
    }
}

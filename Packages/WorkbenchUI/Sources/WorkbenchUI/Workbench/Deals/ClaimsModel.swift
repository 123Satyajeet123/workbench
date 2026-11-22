import Foundation
import Observation
import WorkbenchCore

@Observable
final class ClaimsModel {
    struct DealClaims: Equatable {
        var claims: [Claim] = []
        var chosen: Set<Int64> = []
        var checks: [ClaimCheck] = []

        func check(of claim: Claim) -> ClaimCheck? { checks.first { $0.claim == claim.id } }
    }

    private(set) var byDeal: [String: DealClaims] = [:]
    private(set) var busy: Set<String> = []
    let problems = ProblemSlot()

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let me: () -> String
    @ObservationIgnored private let makeModel: (ModelChoice) -> RecordedModel
    @ObservationIgnored private let openSession: () throws -> WebSession
    @ObservationIgnored private let deckParts: (WorkObject) throws -> [MailPart]

    init(
        store: Store, me: @escaping () -> String, web: WebResearchSettings,
        makeModel: ((ModelChoice) -> RecordedModel)? = nil, openSession: (() throws -> WebSession)? = nil,
        deckParts: ((WorkObject) throws -> [MailPart])? = nil
    ) {
        self.store = store
        self.me = me
        self.makeModel = makeModel ?? { $0.model(store: store) }
        self.openSession = openSession ?? { try web.openSession() }
        self.deckParts =
            deckParts ?? { deal in
                let mine = deal.items.filter { $0.event.author == me() && $0.item.source == .mail }
                return try mine.compactMap(\.item.itemID).flatMap { try store.queries.threadParts(ofItem: $0) }
            }
    }

    func state(of deal: WorkObject) -> DealClaims { byDeal[deal.id] ?? DealClaims() }

    func refresh(_ deal: WorkObject) {
        problems.attempt("read the claims") {
            byDeal[deal.id] = DealClaims(
                claims: try store.queries.claims(of: deal.id),
                chosen: Set(try store.queries.chosenClaims(of: deal.id)),
                checks: try store.queries.claimChecks(of: deal.id))
        }
    }

    func toggle(_ claim: Claim, in deal: WorkObject) {
        var chosen = state(of: deal).chosen
        if let id = claim.id { chosen.formSymmetricDifference([id]) }
        problems.attempt("save the choice") { try store.choose(claims: chosen.sorted(), deal: deal.id) }
        refresh(deal)
    }

    func extract(from deal: WorkObject) async {
        guard busy.insert(deal.id).inserted else { return }
        defer { busy.remove(deal.id) }
        do {
            let parts = Array(Dictionary(grouping: try deckParts(deal), by: \.id).values.compactMap(\.first))
                .sorted { ($0.id ?? 0) < ($1.id ?? 0) }
            guard let label = parts.first?.label else {
                problems.show("This deal has no deck or mail text on this Mac to read claims from.")
                return
            }
            guard
                let grant = try store.currentPolicy().authorize(
                    CaptureRequest(kind: .mail, label: label), at: store.clock()
                )
                .grant
            else {
                problems.show("Mail is switched off for the \(label) label, so its text is not read.")
                return
            }
            let extractor = ClaimExtractor(model: makeModel(try ModelChoice.saved(in: store)))
            let found = try await extractor.extract(deal: deal.id, lines: parts.compactMap(\.evidence))
            if let run = found.run, !found.claims.isEmpty {
                let known = Set(try store.queries.claims(of: deal.id).map { $0.text.comparable })
                try store.saveClaims(
                    found.claims.filter { !known.contains($0.text.comparable) }, run: run, grant: grant)
            }
            problems.dismiss()
        } catch {
            problems.report("read the claims", error)
        }
        refresh(deal)
    }

    func checkChosen(in deal: WorkObject) async {
        guard busy.insert(deal.id).inserted else { return }
        defer { busy.remove(deal.id) }
        let current = state(of: deal)
        let chosen = current.claims.filter { $0.id.map(current.chosen.contains) ?? false }
        do {
            for claim in chosen {
                let session = try openSession()
                let checker = ClaimChecker(model: makeModel(try ModelChoice.saved(in: store)), session: session)
                let done = try await checker.check(claim, company: deal.title)
                try store.saveCheck(done.check, claimQuote: claim.quote, run: done.run, session: session)
                refresh(deal)
            }
            problems.dismiss()
        } catch let block as WebBlock {
            problems.show(block.localizedDescription)
        } catch {
            problems.report("check the claims", error)
        }
        refresh(deal)
    }

    func markVerdict(_ check: ClaimCheck, as mark: Mark, in deal: WorkObject) {
        guard let id = check.id else { return }
        problems.attempt("save the mark") { try store.mark(item: id, as: mark) }
        refresh(deal)
    }

    func markQuote(_ check: ClaimCheck, as mark: Mark, in deal: WorkObject) {
        guard let id = check.id else { return }
        problems.attempt("save the mark") { try store.markQuote(of: id, as: mark) }
        refresh(deal)
    }
}

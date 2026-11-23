import Foundation
import Kernel
import Observation
import WorkbenchCore

/// A deal's checkable work, over the evidence of the deal from any source: the claims read from it, typed by hand or
/// taken from a file added to it, the checks of chosen claims on the web, and the rating against the team's thesis. A
/// check runs only through `WebResearchSettings.openSession`, so the consent, the key and the cap come first.
@Observable
final class ClaimsModel {
    struct DealClaims: Equatable {
        var claims: [Claim] = []
        var chosen: Set<Int64> = []
        var checks: [ClaimCheck] = []
        /// The items behind the claims, the checks and the rating, by id, for the rows that show them.
        var items: [Int64: Item] = [:]
        /// The latest rating fact of the deal, and the call the team's criteria make from it now.
        var rating: Item?
        var triage: Triage?

        func check(of claim: Claim) -> ClaimCheck? { checks.first { $0.claim == claim.id } }
    }

    private(set) var byDeal: [String: DealClaims] = [:]
    private(set) var busy: Set<String> = []
    let problems = ProblemSlot()

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let me: () -> String
    @ObservationIgnored private let owner: Result<PersonID, any Error>
    @ObservationIgnored private let makeModel: ModelMaker
    @ObservationIgnored private let openSession: () throws -> WebSession
    @ObservationIgnored private let evidence: (WorkObject) throws -> [Evidence]

    init(
        store: Store, me: @escaping () -> String, web: WebResearchSettings,
        owner: Result<PersonID, any Error> = PageHost.noOwner, makeModel: ((ModelChoice) -> RecordedModel)? = nil,
        openSession: (() throws -> WebSession)? = nil, evidence: ((WorkObject) throws -> [Evidence])? = nil
    ) {
        self.store = store
        self.me = me
        self.owner = owner
        self.makeModel = ModelMaker(store: store, make: makeModel)
        self.openSession = openSession ?? { try web.openSession() }
        self.evidence = evidence ?? { try store.queries.evidence(of: $0, author: me()) }
    }

    func state(of deal: WorkObject) -> DealClaims { byDeal[deal.id] ?? DealClaims() }

    func refresh(_ deal: WorkObject) {
        problems.attempt("read the claims") {
            let claims = try store.queries.claims(of: deal.id)
            let checks = try store.queries.claimChecks(of: deal.id)
            let rating = try store.queries.rating(of: deal.id)
            let triage = try rating.flatMap { rating in try store.queries.thesis()?.triage(rating.fields) }
            let items = try store.queries.items(
                ids: claims.compactMap(\.id) + checks.compactMap(\.id) + [rating?.id].compactMap { $0 })
            byDeal[deal.id] = DealClaims(
                claims: claims, chosen: Set(try store.queries.chosenClaims(of: deal.id)), checks: checks,
                items: Dictionary(items.compactMap { item in item.id.map { ($0, item) } }) { first, _ in first },
                rating: rating, triage: triage)
        }
    }

    /// The proof model of the section's rows: a fact's lines are the ones its run read, from any source.
    func proofModel(crew: Crew) -> ProofModel {
        let store = store
        return ProofModel(
            crew: crew, store: store, title: { $0["text"] },
            lines: { item in
                try store.queries.proofLines(of: item).map {
                    ChatLine(id: $0.line.number, time: $0.line.time, text: $0.line.evidence.line, isCited: $0.isCited)
                }
            })
    }

    func toggle(_ claim: Claim, in deal: WorkObject) {
        var chosen = state(of: deal).chosen
        if let id = claim.id { chosen.formSymmetricDifference([id]) }
        problems.attempt("save the choice") { try store.choose(claims: chosen.sorted(), deal: deal.id) }
        refresh(deal)
    }

    /// Adds a file to the deal: its text becomes lines of the deal's evidence, written by the person.
    func addFile(_ url: URL, to deal: WorkObject) {
        do {
            let pages = try store.addFile(
                try Data(contentsOf: url), named: url.lastPathComponent, to: deal.id, owner: try owner.get())
            if pages == 0 {
                problems.show("No text could be read from \(url.lastPathComponent).")
            } else {
                problems.dismiss()
            }
        } catch {
            problems.report("add the file", error)
        }
        refresh(deal)
    }

    /// Types a claim on the deal. It can be chosen and checked like a claim read from a file.
    func addClaim(_ words: String, to deal: WorkObject) {
        problems.attempt("add the claim", clearing: true) {
            try store.addTypedClaim(words, to: deal.id, owner: try owner.get())
        }
        refresh(deal)
    }

    /// Reads the claims of the deal's evidence with one model call. The consent of every source of its lines must
    /// still allow it.
    func extract(from deal: WorkObject) async {
        guard busy.insert(deal.id).inserted else { return }
        defer { busy.remove(deal.id) }
        do {
            let lines = try evidence(deal)
            guard !lines.isEmpty else {
                problems.show("This deal has no evidence on this Mac to read claims from. Add a file or link an item.")
                return
            }
            let grants = try store.grants(for: lines)
            guard let types = try store.queries.claimTypes() else {
                problems.show("No machine lists claim types, so there is nothing to read claims for.")
                return
            }
            let extractor = ClaimExtractor(model: try makeModel.current(), types: types)
            let found = try await extractor.extract(deal: deal.id, lines: lines)
            if let run = found.run, !found.claims.isEmpty {
                let known = Set(try store.queries.claims(of: deal.id).map { $0.text.comparable })
                for claim in found.claims where !known.contains(claim.text.comparable) {
                    guard let consent = lines.first(where: { $0.id == claim.line })?.consent,
                        let grant = grants[consent]
                    else { continue }
                    try store.saveClaims([claim], run: run, grant: grant)
                }
            }
            problems.dismiss()
        } catch let block as ReadBlock {
            problems.show(block.localizedDescription)
        } catch {
            problems.report("read the claims", error)
        }
        refresh(deal)
    }

    /// Rates the deal against the team's thesis, over the deal's evidence from any source. The rating is a fact on the
    /// deal that the person can mark.
    func rate(_ deal: WorkObject) async {
        guard busy.insert(deal.id).inserted else { return }
        defer { busy.remove(deal.id) }
        do {
            let lines = try evidence(deal)
            guard !lines.isEmpty else {
                problems.show("This deal has no evidence on this Mac to rate. Add a file or link an item.")
                return
            }
            guard let criteria = try store.queries.thesis() else {
                problems.show("No machine has criteria, so there is no thesis to rate against.")
                return
            }
            let grants = try store.grants(for: lines)
            let rater = DealRater(model: try makeModel.current(), criteria: criteria)
            if let rating = try await rater.rate(deal: deal.id, company: deal.name, lines: lines),
                let grant = rating.source.flatMap({ kind in grants.first { $0.key.kind == kind }?.value })
            {
                try store.saveRating(rating, grant: grant)
                problems.dismiss()
            } else {
                problems.show("Nothing in the evidence settles the rules, so the deal is not rated.")
            }
        } catch let block as ReadBlock {
            problems.show(block.localizedDescription)
        } catch {
            problems.report("rate the deal", error)
        }
        refresh(deal)
    }

    /// Marks a fact of the deal: a claim, a verdict or the rating.
    func mark(_ item: Item, as mark: Mark, in deal: WorkObject) {
        guard let id = item.id else { return }
        problems.attempt("save the mark") { try store.mark(item: id, as: mark) }
        refresh(deal)
    }

    /// Checks each chosen claim. A block (consent off, no key, cap reached) stops at once and says why. A claim with
    /// no known label is refused on its own, the refusal is shown, and the next claim is checked.
    func checkChosen(in deal: WorkObject) async {
        guard busy.insert(deal.id).inserted else { return }
        defer { busy.remove(deal.id) }
        let current = state(of: deal)
        let chosen = current.claims.filter { $0.id.map(current.chosen.contains) ?? false }
        var refusals: [String] = []
        do {
            let types = try store.queries.claimTypes() ?? []
            for claim in chosen {
                let session = try openSession()
                let checker = ClaimChecker(
                    model: try makeModel.current(), session: session, types: types)
                do {
                    let done = try await checker.check(claim, company: deal.name)
                    try store.saveCheck(done.check, claimQuote: claim.quote, run: done.run, session: session)
                } catch WebBlock.labelUnknown {
                    refusals.append("\u{201C}\(claim.text)\u{201D}: \(WebBlock.labelUnknown.localizedDescription)")
                }
                refresh(deal)
            }
            if refusals.isEmpty { problems.dismiss() } else { problems.show(refusals.joined(separator: "\n")) }
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

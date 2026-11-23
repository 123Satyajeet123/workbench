import Foundation
import Kernel

/// One claim the web check settled, with the page its quote came from.
public struct CheckedClaim: Sendable {
    public let claim: Claim
    public let check: ClaimCheck
    public let run: RunID
    public let page: FetchedPage?

    public init(claim: Claim, check: ClaimCheck, run: RunID, page: FetchedPage?) {
        self.claim = claim
        self.check = check
        self.run = run
        self.page = page
    }
}

/// The on-device verifier, loaded once from the model folder when it exists. Until it is there, a claim is `unknown`.
/// Hinglish and other text go to the model judge it is given.
public actor GroundingSource {
    public static let folder = URL.applicationSupportDirectory.appending(path: "Workbench/models/grounding")

    private let folder: URL
    private var onDevice: (any GroundingVerifier)?

    public init(folder: URL = GroundingSource.folder) { self.folder = folder }

    public func verifier(modelJudge: (any GroundingVerifier)?) async -> any GroundingVerifier {
        if onDevice == nil, FileManager.default.fileExists(atPath: folder.path) {
            onDevice = try? await CoreMLScorer.verifier(folder: folder)
        }
        return LanguageRoutedGrounding(onDevice: onDevice ?? NoGrounding(), modelJudge: modelJudge)
    }
}

/// Judges the supported claims of a round of web checks as one work product, with the checker's output as its input:
/// each claim is cited to the page its quote is in. The pages are kept as snapshots, the product is kept with its split
/// role, and the verdicts go to the one trace. A claim the check did not support has no cite, so it is not a claim of
/// the product.
public struct ClaimCheckJudge: Sendable {
    public let store: Store
    public let grounding: any GroundingVerifier

    public init(store: Store, grounding: any GroundingVerifier) {
        self.store = store
        self.grounding = grounding
    }

    /// Does nothing when no claim of the round was supported with a quote and a page: there is nothing to cite.
    public func judge(_ checked: [CheckedClaim], company: String, deal: String, session: WebSession) async throws {
        var claims: [ProductClaim] = []
        var run: RunID?
        for item in checked where item.check.verdict == .supported && !item.check.quote.isEmpty {
            guard let page = item.page else { continue }
            let snapshot = try store.savePageSnapshot(page, session: session)
            claims.append(
                ProductClaim(
                    text: item.claim.text, cites: [Cite(source: .page(snapshot: snapshot), quote: item.check.quote)]))
            run = run ?? item.run
        }
        guard let run, !claims.isEmpty else { return }
        let product = WorkProduct(
            taskType: WorkProduct.researchTask, deal: deal, subject: company,
            question: "Which claims about \(company) do web pages support?",
            text: claims.map(\.text).joined(separator: "\n"), claims: claims)
        let judge = Judge(
            library: StoreCiteLibrary(store.queries), gate: DriverGate(policy: try store.currentPolicy()),
            grounding: grounding)
        let saved = try store.saveProduct(
            product, writer: run, grant: session.webGrant, label: Self.sharedLabel(of: checked.map(\.claim)),
            versions: judge.versions)
        try store.saveJudgment(await judge.judge(saved.shown(from: product)), of: saved)
    }

    /// The label every claim has, or nil when they differ or any is unknown: no reader is then known.
    static func sharedLabel(of claims: [Claim]) -> Label? {
        guard let first = claims.first?.label, claims.allSatisfy({ $0.label == first }) else { return nil }
        return first
    }
}

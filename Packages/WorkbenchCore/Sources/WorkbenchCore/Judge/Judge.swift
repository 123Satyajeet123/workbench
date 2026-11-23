import Foundation

/// The judge of work products (ADR-020): one module, any product with claims and cites. Stage 0 is the one verifier
/// applied to each claim and is final. Stage 1 asks a grounding verifier whether the cited text supports the claim.
/// Stage 2 is a rubric judge whose verdicts are advice. The verdict of a claim comes from stages 0 and 1; the verdict of
/// a product is all of its claims together, and unknown never counts as pass.
public struct Judge: Sendable {
    public let library: any CiteLibrary
    public let gate: DriverGate
    public let grounding: any GroundingVerifier
    public let rubric: RubricJudge?
    public let settings: Verifier.Settings

    public init(
        library: any CiteLibrary, gate: DriverGate, grounding: any GroundingVerifier, rubric: RubricJudge? = nil,
        settings: Verifier.Settings = Verifier.Settings()
    ) {
        self.library = library
        self.gate = gate
        self.grounding = grounding
        self.rubric = rubric
        self.settings = settings
    }

    /// The version of every part that decides, by name. A trace row repeats it; a freeze hashes it.
    public var versions: JudgeVersions {
        JudgeVersions(parts: [
            "structure": JudgeVersions.structure, "grounding": grounding.identity.version,
            "rubric": rubric?.rubric.version ?? "none",
        ])
    }

    public func judge(_ product: WorkProduct) async -> ProductJudgment {
        let verifier = Verifier(window: EvidenceSet(lines: []), settings: settings)
        var claims: [ClaimJudgment] = []
        for claim in product.claims {
            let outcome = verifier.structure(of: claim, subject: product.subject, library: library, gate: gate)
            let structure = StageVerdict(outcome)
            claims.append(
                ClaimJudgment(
                    structure: structure,
                    grounding: outcome.verdict == .pass ? await grounded(claim, outcome.spans) : nil))
        }
        let advice = await rubric?.advise(on: product, library: library) ?? []
        return ProductJudgment(claims: claims, advice: advice, versions: versions)
    }

    private func grounded(_ claim: ProductClaim, _ spans: [CitedSpan]) async -> StageVerdict {
        let premise = spans.map(\.premise).joined(separator: "\n")
        do {
            let found = try await grounding.ground(claim: claim.text, premise: premise)
            return StageVerdict(
                stage: .grounding, verdict: found.verdict, reason: Self.reason(of: found.verdict), detail: found.quote,
                score: found.score, run: found.run)
        } catch {
            return StageVerdict(stage: .grounding, verdict: .unknown, reason: "verifier_error", detail: "\(error)")
        }
    }

    private static func reason(of verdict: Verdict) -> String {
        switch verdict {
        case .pass: "supported"
        case .fail: "unsupported"
        case .unknown: "undecided"
        }
    }
}

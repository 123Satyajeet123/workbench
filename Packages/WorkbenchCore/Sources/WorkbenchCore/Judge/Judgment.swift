import Foundation

extension Verdict {
    /// The verdict of a whole from its parts: one fail fails it, else one unknown leaves it unknown, and only all-pass
    /// passes. Nothing passes: unknown never counts as pass.
    public static func combined(_ parts: [Verdict]) -> Verdict {
        if parts.contains(.fail) { return .fail }
        if parts.isEmpty || parts.contains(.unknown) { return .unknown }
        return .pass
    }
}

public enum JudgeStage: String, Codable, Sendable, CaseIterable {
    /// Code: cites, facts, source and date. A gate; a failure is final.
    case structure
    /// A learned verifier or a model judge: does the cited text support the claim. A gate per claim.
    case grounding
    /// A rubric judge. Advice; never a gate.
    case quality
    /// The verdict of the whole product.
    case product
}

/// One row of the trace: what a stage decided, why, and the versions of every part that decided it.
public struct StageVerdict: Codable, Sendable, Equatable {
    public var stage: JudgeStage
    public var verdict: Verdict
    /// A rule or a short name for the outcome, such as `fact_not_cited` or `supported`.
    public var reason: String
    /// The words that show it: the missing facts, the model's quote, the address.
    public var detail: String
    public var score: Double?
    /// The rubric item of a quality verdict.
    public var rubricItem: String?
    /// The model run behind it, when a model decided.
    public var run: RunID?

    public init(
        stage: JudgeStage, verdict: Verdict, reason: String, detail: String = "", score: Double? = nil,
        rubricItem: String? = nil, run: RunID? = nil
    ) {
        self.stage = stage
        self.verdict = verdict
        self.reason = reason
        self.detail = detail
        self.score = score
        self.rubricItem = rubricItem
        self.run = run
    }

    init(_ outcome: StructureOutcome) {
        self.init(
            stage: .structure, verdict: outcome.verdict, reason: outcome.rule?.rawValue ?? "structure_ok",
            detail: outcome.detail)
    }
}

/// The versions of every part of a judge, by name. The hash names the whole: a freeze records it, and every
/// trace row repeats it.
public struct JudgeVersions: Codable, Sendable, Equatable {
    public var parts: [String: String]

    public init(parts: [String: String]) { self.parts = parts }

    public var hash: String { Digest.sha256((try? Coding.json(parts)) ?? "") }

    /// The code of stage 0. A change to its rules is a new version.
    public static let structure = "structure-1"
}

/// What the judge decided about one claim. Stage 0 failing leaves no grounding verdict: the failure is final.
public struct ClaimJudgment: Sendable, Equatable {
    public var structure: StageVerdict
    public var grounding: StageVerdict?

    public var verdict: Verdict { grounding?.verdict ?? structure.verdict }
}

/// What the judge decided about a product: a verdict per claim, one for the product, and the advice of stage 2.
public struct ProductJudgment: Sendable, Equatable {
    public var claims: [ClaimJudgment]
    public var advice: [StageVerdict]
    public var versions: JudgeVersions

    public var verdict: Verdict { Verdict.combined(claims.map(\.verdict)) }
}

extension StageVerdict {
    /// What the verdict says, in the words a person reads on a page.
    public var plainWords: String {
        switch stage {
        case .structure: structureWords
        case .grounding:
            switch verdict {
            case .pass: "The cited words support it."
            case .fail: "The cited words do not support it."
            case .unknown: reason == "verifier_error" ? "The check could not run." : "The check could not decide."
            }
        case .quality, .product: reason
        }
    }

    private var structureWords: String {
        guard verdict == .fail else { return "Cites found, and its facts are in them." }
        switch DropRule(rawValue: reason) {
        case .noCite: return "It has no cite."
        case .sourceMissing: return "The cited page or line is not stored."
        case .snapshotChanged: return "The stored page no longer matches its record."
        case .sourceRefused: return "The cited page may not be read."
        case .pageDateMissing: return "The cited page states no date."
        case .quoteNotInLines, .quoteTooShort: return "Its quote is not in the cited text."
        case .factNotCited: return "Not in the cited words: \(detail)."
        default: return "It failed a check."
        }
    }
}

import Foundation
import NaturalLanguage

/// Which model made a verdict and how it was set: the name, a hash of its weights, and its parameters. A freeze and
/// every trace row name it, so a verdict is tied to the exact verifier.
public struct GroundingIdentity: Codable, Sendable, Equatable {
    public var name: String
    public var weights: String
    public var parameters: String

    public init(name: String, weights: String = "", parameters: String = "") {
        self.name = name
        self.weights = weights
        self.parameters = parameters
    }

    public var version: String {
        [name, weights.prefix(12).description, parameters].filter { !$0.isEmpty }.joined(separator: "@")
    }
}

/// What a grounding stage found for one claim and the text cited for it.
public struct Grounding: Sendable, Equatable {
    public var verdict: Verdict
    public var score: Double?
    /// The words that show the verdict: found in the premise, as a model judge must give them back.
    public var quote: String
    public var run: RunID?

    public init(verdict: Verdict, score: Double? = nil, quote: String = "", run: RunID? = nil) {
        self.verdict = verdict
        self.score = score
        self.quote = quote
        self.run = run
    }
}

/// Stage 1: does the cited text support the claim. Verifier models sit behind this protocol, so one can replace
/// another. A verifier that cannot decide says `unknown`, and unknown never counts as pass.
public protocol GroundingVerifier: Sendable {
    var identity: GroundingIdentity { get }
    func ground(claim: String, premise: String) async throws -> Grounding
}

/// A model that scores how likely a premise supports a claim, from 0 to 1. It decides nothing alone: a band does.
public protocol SupportScorer: Sendable {
    var identity: GroundingIdentity { get }
    func support(of claim: String, premise: String) async throws -> Double
}

/// The two cuts on a support score: below `failBelow` the claim is unsupported, from `passFrom` it is supported, and
/// between them the verifier does not know. The cuts are data, chosen on dev marks and frozen with the judge.
public struct ScoreBand: Codable, Sendable, Equatable {
    public var failBelow: Double
    public var passFrom: Double

    public init(failBelow: Double, passFrom: Double) {
        self.failBelow = failBelow
        self.passFrom = passFrom
    }

    public func verdict(of score: Double) -> Verdict {
        if score >= passFrom { return .pass }
        return score < failBelow ? .fail : .unknown
    }

    public var version: String { String(format: "band-%.2f-%.2f", failBelow, passFrom) }
}

/// A scorer read through a band: a verifier.
public struct BandedGrounding: GroundingVerifier {
    public let scorer: any SupportScorer
    public let band: ScoreBand

    public init(scorer: any SupportScorer, band: ScoreBand) {
        self.scorer = scorer
        self.band = band
    }

    public var identity: GroundingIdentity {
        var identity = scorer.identity
        identity.parameters = band.version
        return identity
    }

    public func ground(claim: String, premise: String) async throws -> Grounding {
        let score = try await scorer.support(of: claim, premise: premise)
        return Grounding(verdict: band.verdict(of: score), score: score)
    }
}

/// The verifier of a Mac that has no model folder yet: it decides nothing, and says so.
public struct NoGrounding: GroundingVerifier {
    public init() {}

    public var identity: GroundingIdentity { GroundingIdentity(name: "no-verifier") }

    public func ground(claim: String, premise: String) async throws -> Grounding { Grounding(verdict: .unknown) }
}

/// The language a text is written in, as far as the platform can tell. Latin script that the platform reads as
/// English is `english`; Devanagari is `hindi`; anything else, such as Hinglish in Latin letters, is `other`.
public enum ClaimLanguage: String, Codable, Sendable, CaseIterable {
    case english
    case hindi
    case other

    /// The share of letters in Devanagari from which a text is Hindi.
    static let devanagariShare = 0.3
    /// The least confidence at which the platform's guess of English counts.
    static let englishConfidence = 0.9

    public init(_ text: String) {
        let letters = text.unicodeScalars.filter { $0.properties.isAlphabetic }
        let devanagari = letters.filter { (0x0900...0x097F).contains($0.value) }
        if !letters.isEmpty, Double(devanagari.count) / Double(letters.count) >= Self.devanagariShare {
            self = .hindi
            return
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[.english] ?? 0
        self = recognizer.dominantLanguage == .english && confidence >= Self.englishConfidence ? .english : .other
    }
}

/// A verifier for each language, as probe P-J1 found them (dev): the on-device verifier for English and for Hindi in
/// Devanagari, where it beat the lexical control; a model judge of another family than the writer for Hinglish and any
/// other text, where no verifier beat the control.
public struct LanguageRoutedGrounding: GroundingVerifier {
    public let onDevice: any GroundingVerifier
    public let modelJudge: (any GroundingVerifier)?

    public init(onDevice: any GroundingVerifier, modelJudge: (any GroundingVerifier)?) {
        self.onDevice = onDevice
        self.modelJudge = modelJudge
    }

    public var identity: GroundingIdentity {
        GroundingIdentity(
            name: "routed", weights: "",
            parameters: "on-device=\(onDevice.identity.version);model-judge=\(modelJudge?.identity.version ?? "none")")
    }

    public func ground(claim: String, premise: String) async throws -> Grounding {
        guard ClaimLanguage(claim) == .other else { return try await onDevice.ground(claim: claim, premise: premise) }
        guard let modelJudge else { return Grounding(verdict: .unknown) }
        return try await modelJudge.ground(claim: claim, premise: premise)
    }
}

/// Splits a premise into pieces that each fit a model's input, on sentence boundaries; a sentence that does not fit
/// alone is cut on words. `fits` says whether a text fits.
enum PremiseChunker {
    static func chunks(of premise: String, fits: (String) -> Bool) -> [String] {
        guard !fits(premise) else { return [premise] }
        var chunks: [String] = []
        var current = ""
        for sentence in sentences(of: premise) {
            let joined = current.isEmpty ? sentence : current + " " + sentence
            if fits(joined) {
                current = joined
            } else {
                if !current.isEmpty { chunks.append(current) }
                let pieces = fits(sentence) ? [sentence] : wordWindows(of: sentence, fits: fits)
                chunks += pieces.dropLast()
                current = pieces.last ?? ""
            }
        }
        return current.isEmpty ? chunks : chunks + [current]
    }

    private static func sentences(of text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var found: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            found.append(text[range].trimmingCharacters(in: .whitespacesAndNewlines))
            return true
        }
        return found.filter { !$0.isEmpty }
    }

    private static func wordWindows(of text: String, fits: (String) -> Bool) -> [String] {
        var windows: [String] = []
        var current: [Substring] = []
        for word in text.split(separator: " ") {
            if !current.isEmpty, !fits((current + [word]).joined(separator: " ")) {
                windows.append(current.joined(separator: " "))
                current = []
            }
            current.append(word)
        }
        return current.isEmpty ? windows : windows + [current.joined(separator: " ")]
    }
}

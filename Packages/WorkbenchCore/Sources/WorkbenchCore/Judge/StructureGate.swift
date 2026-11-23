import Foundation
import NaturalLanguage

/// A cite found in its stored text: the words, where they are, and the sentences around them that stage 1 reads.
public struct CitedSpan: Sendable, Equatable {
    public var source: Cite.Source
    public var quote: String
    public var span: QuoteSpan
    /// The sentences of the stored text that the quote lies in.
    public var premise: String
}

/// What stage 0 decided about one claim. A failure is final: it names the rule it broke, and no later stage overrides
/// it.
public struct StructureOutcome: Sendable, Equatable {
    public var verdict: Verdict
    public var rule: DropRule?
    /// The facts or the address that broke the rule, in words; empty when it passed.
    public var detail: String
    public var spans: [CitedSpan]

    static func failed(_ rule: DropRule, _ detail: String = "") -> StructureOutcome {
        StructureOutcome(verdict: .fail, rule: rule, detail: detail, spans: [])
    }

    static func passed(_ spans: [CitedSpan]) -> StructureOutcome {
        StructureOutcome(verdict: .pass, rule: nil, detail: "", spans: spans)
    }
}

extension Verifier {
    /// Stage 0 of the judge: the one verifier applied to a claim of a work product. In order, and the first break is
    /// final:
    /// 1. the claim has a cite;
    /// 2. each cite's text is stored, and a page's text still has its recorded hash;
    /// 3. the cite's words are in that text, found as every quote is (exact after the fold);
    /// 4. a page passes the driver gate (consent apart: reading stored text needs no consent) and states a date;
    /// 5. every amount, month and proper name of the claim is in the cited words.
    ///
    /// It reads where a claim points and which facts it states, never what it means.
    public func structure(
        of claim: ProductClaim, subject: String, library: any CiteLibrary, gate: DriverGate
    ) -> StructureOutcome {
        guard !claim.cites.isEmpty else { return .failed(.noCite) }
        var spans: [CitedSpan] = []
        for cite in claim.cites {
            switch citedSpan(of: cite, library: library, gate: gate) {
            case .found(let span): spans.append(span)
            case .broken(let outcome): return outcome
            }
        }
        let vocabulary = CitedVocabulary(of: spans.map(\.quote).joined(separator: " "))
        let missing = ClaimFacts(of: claim.text, ignoring: subject).missing(from: vocabulary)
        guard missing.isEmpty else { return .failed(.factNotCited, missing.joined(separator: ", ")) }
        return .passed(spans)
    }

    private enum Resolution {
        case found(CitedSpan)
        case broken(StructureOutcome)
    }

    private func citedSpan(of cite: Cite, library: any CiteLibrary, gate: DriverGate) -> Resolution {
        let stored: CitedText
        do {
            guard let found = try library.text(of: cite.source) else { return .broken(.failed(.sourceMissing)) }
            stored = found
        } catch {
            return .broken(.failed(.verifierError, "\(error)"))
        }
        if let refusal = sourceRefusal(of: stored, gate: gate) { return .broken(refusal) }
        let line = Evidence(id: 1, start: .distantPast, line: stored.text, quotable: [stored.text])
        do {
            let span = try quote(cite.quote, in: [line])
            return .found(
                CitedSpan(
                    source: cite.source, quote: cite.quote, span: span,
                    premise: Self.sentences(of: stored.text, around: span)))
        } catch let refusal as Refusal {
            return .broken(.failed(refusal.rule))
        } catch {
            return .broken(.failed(.verifierError, "\(error)"))
        }
    }

    private func sourceRefusal(of stored: CitedText, gate: DriverGate) -> StructureOutcome? {
        guard case .page(let url, let fetchedAt, let hash, let pageDate) = stored.origin else { return nil }
        guard Digest.sha256(stored.text) == hash else { return .failed(.snapshotChanged) }
        if let refusal = gate.refusal(for: DriverRequest(url: url), at: fetchedAt), !refusal.isConsent {
            return .failed(.sourceRefused, refusal.description)
        }
        return pageDate == nil ? .failed(.pageDateMissing) : nil
    }

    /// The sentences of `text` that the span touches, joined by a space.
    static func sentences(of text: String, around span: QuoteSpan) -> String {
        let normal = text.nfc
        let scalars = normal.unicodeScalars
        guard let lower = scalars.index(scalars.startIndex, offsetBy: span.start, limitedBy: scalars.endIndex),
            let upper = scalars.index(scalars.startIndex, offsetBy: span.end, limitedBy: scalars.endIndex)
        else { return normal }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normal
        var touched: [String] = []
        tokenizer.enumerateTokens(in: normal.startIndex..<normal.endIndex) { range, _ in
            if range.lowerBound < upper && range.upperBound > lower { touched.append(String(normal[range])) }
            return true
        }
        return touched.isEmpty ? normal : touched.joined(separator: " ")
    }
}

extension DriverRefusal {
    fileprivate var isConsent: Bool {
        if case .consent = self { true } else { false }
    }
}

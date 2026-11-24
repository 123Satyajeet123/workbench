import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct JudgeTests {
    private let source = Cite.Source.line(Data(repeating: 1, count: 32))
    private let sentence = "Atomicwork has raised $11 Mn in its seed funding round, led by Blume Ventures."
    private let gate = DriverGate(policy: CapturePolicy())

    private func structure(_ text: String, cite quote: String?, cited: String? = nil) -> StructureOutcome {
        let library = FixedCiteLibrary([SourceText(source: source, text: cited ?? sentence, origin: .line)])
        let claim = ProductClaim(text: text, cites: quote.map { [Cite(source: source, quote: $0)] } ?? [])
        return Verifier(window: EvidenceSet(lines: [])).structure(
            of: claim, subject: "Atomicwork", library: library, gate: gate)
    }

    @Test func aClaimPassesStageZeroWhenItsFactsAreInTheCitedWords() {
        let outcome = structure("Atomicwork raised $11 million in its seed round.", cite: "raised $11 Mn in its seed")
        #expect(outcome.verdict == .pass && outcome.rule == nil)
    }

    @Test func stageZeroStopsEachBreakAndNamesTheRule() {
        #expect(structure("It raised money.", cite: nil).rule == .noCite)
        #expect(structure("Atomicwork raised $11 million.", cite: "raised $50 Mn").rule == .quoteNotInLines)
        let amount = structure("Atomicwork raised $20 million in its seed round.", cite: "raised $11 Mn in its seed")
        #expect(amount.rule == .factNotCited && amount.verdict == .fail)
        let name = structure("Atomicwork was led by Sequoia.", cite: "led by Blume Ventures")
        #expect(name.rule == .factNotCited)
    }

    @Test func aMissingSourceIsAFailureAndNotAPass() {
        let library = FixedCiteLibrary([])
        let claim = ProductClaim(text: "Atomicwork raised money.", cites: [Cite(source: source, quote: "raised")])
        let outcome = Verifier(window: EvidenceSet(lines: [])).structure(
            of: claim, subject: "Atomicwork", library: library, gate: gate)
        #expect(outcome.rule == .sourceMissing && outcome.verdict == .fail)
    }

    @Test func aPageNeedsItsHashAndADate() {
        let url = URL(string: "https://news.example/a")!
        let page = Cite.Source.page(snapshot: 1)
        let claim = ProductClaim(text: "Atomicwork raised money.", cites: [Cite(source: page, quote: "raised")])
        func outcome(hash: String, date: Date?) -> StructureOutcome {
            let stored = SourceText(
                source: page, text: sentence,
                origin: .page(url: url, fetchedAt: t0, contentHash: hash, pageDate: date))
            return Verifier(window: EvidenceSet(lines: [])).structure(
                of: claim, subject: "Atomicwork", library: FixedCiteLibrary([stored]), gate: gate)
        }
        #expect(outcome(hash: Digest.sha256(sentence), date: t0).verdict == .pass)
        #expect(outcome(hash: Digest.sha256("other"), date: t0).rule == .snapshotChanged)
        #expect(outcome(hash: Digest.sha256(sentence), date: nil).rule == .pageDateMissing)
    }

    @Test func anAmountIsOneAmountWhateverItsWriting() {
        let cited = CitedVocabulary(of: "has raised $11 Mn in its seed funding round")
        #expect(ClaimFacts(of: "It raised $11 million.").missing(from: cited).isEmpty)
        #expect(ClaimFacts(of: "It raised $20 million.").missing(from: cited).count == 1)
        #expect(ClaimFacts(of: "It raised 11 crore rupees.").missing(from: cited).count == 1)
    }

    @Test func unknownNeverCountsAsPass() {
        #expect(Verdict.combined([]) == .unknown)
        #expect(Verdict.combined([.pass, .unknown]) == .unknown)
        #expect(Verdict.combined([.pass, .pass]) == .pass)
        #expect(Verdict.combined([.unknown, .fail]) == .fail)
    }

    @Test func aBandCutsAScoreIntoThreeVerdicts() {
        let band = ScoreBand(failBelow: 0.2, passFrom: 0.7)
        #expect(band.verdict(of: 0.1) == .fail && band.verdict(of: 0.2) == .unknown)
        #expect(band.verdict(of: 0.69) == .unknown && band.verdict(of: 0.7) == .pass)
    }

    @Test func aTieBetweenOrdersIsUnknownAndTheMajorityOfRunsDecides() {
        #expect(RubricTally.resolve([[.pass, .pass], [.pass, .pass], [.fail, .fail]]).verdict == .pass)
        #expect(RubricTally.resolve([[.pass, .fail], [.pass, .fail], [.pass, .fail]]).verdict == .unknown)
        #expect(RubricTally.resolve([[.pass, .pass], [.fail, .fail], [.unknown, .unknown]]).verdict == .unknown)
    }

    @Test func aPremiseThatDoesNotFitIsCutOnSentences() {
        let premise = "One sentence here. Another sentence there. Third one."
        let chunks = PremiseChunker.chunks(of: premise) { $0.count <= 30 }
        #expect(chunks == ["One sentence here.", "Another sentence there.", "Third one."])
        #expect(PremiseChunker.chunks(of: premise) { _ in true } == [premise])
    }

    @Test func aCatchClaimIsMadeWrongInTheKindAsked() throws {
        let claim = ProductClaim(text: "Acme raised $11 million in 2023.", cites: [])
        let amount = try #require(CatchClaim.make(from: claim, kind: .amount))
        let year = try #require(CatchClaim.make(from: claim, kind: .year))
        #expect(amount.text != claim.text && amount.text.contains("2023") && !amount.text.contains("$11 "))
        #expect(year.text.contains("2021") && year.text.contains("$11"))
        #expect(CatchClaim.make(from: claim, kind: .unsupported)?.cites.isEmpty == true)
    }
}

@Suite struct HeldOutGuardTests {
    @Test func aDevReadIsAllowedForEveryUse() throws {
        for use in [DataUse.learning, .tuning, .errorAnalysis, .evaluation(freeze: "f")] {
            try HeldOutGuard.admit(.dev, for: use)
        }
    }

    @Test func aHeldOutReadIsRefusedExceptForAnEvaluation() throws {
        for use in [DataUse.learning, .tuning, .errorAnalysis] {
            #expect(throws: HeldOutRefusal.self) { try HeldOutGuard.admit(.heldOut, for: use) }
        }
        try HeldOutGuard.admit(.heldOut, for: .evaluation(freeze: "f"))
    }

    @Test func theStudyWindowAndAFreezeWindowAreHeldOut() throws {
        let inStudy = try #require(WorkDay("2026-11-25"))
        #expect(SplitRole(day: inStudy, freezes: []) == .heldOut)
        let frozen = Freeze(
            taskType: "research", frozenAt: Date(timeIntervalSince1970: 1_800_000_000), windowDays: 14,
            parts: JudgeVersions(parts: ["structure": "s"]))
        #expect(SplitRole(day: frozen.window.lowerBound, freezes: [frozen]) == .heldOut)
        #expect(SplitRole(day: frozen.window.upperBound, freezes: [frozen]) == .heldOut)
        #expect(!frozen.window.contains(WorkDay(containing: frozen.frozenAt)))
    }
}

@Suite struct AutonomyTests {
    private func clean(_ runs: Int) -> Certificate {
        Certificate(
            answers: (0..<runs).map { _ in Certificate.Answer(wrong: false, chance: RunSettings.standard.pickChance) })
    }

    @Test func noMarksIsAskAndAFrozenJudgeIsSuggest() {
        #expect(Autonomy.computedRung(certificate: Certificate(), hasFrozenJudge: false) == .ask)
        #expect(Autonomy.computedRung(certificate: Certificate(), hasFrozenJudge: true) == .suggest)
    }

    @Test func moreCleanAnswersEarnTheHigherRungs() {
        #expect(Autonomy.computedRung(certificate: clean(50), hasFrozenJudge: true) == .fill)
        #expect(Autonomy.computedRung(certificate: clean(150), hasFrozenJudge: true) == .share)
    }

    @Test func theRungInForceDoesNotMoveByItselfAndIsFlaggedWhenAboveWhatTheMarksSupport() {
        let report = Autonomy.report(
            certificate: Certificate(), hasFrozenJudge: true, applied: .fill, windowIsOpen: true)
        #expect(report.computed == .suggest && report.applied == .fill)
        #expect(report.exceedsCertificate && report.windowIsOpen)
    }

    @Test func predictionPoweredInferenceNeedsAgreementOverEnoughMarks() {
        func agreement(_ marks: Int, wrong: Int) -> JudgeAgreement {
            var found = JudgeAgreement()
            for index in 0..<marks { found.add(judge: .pass, person: index < wrong ? .rejected : .confirmed) }
            return found
        }
        #expect(!PredictionPoweredInference.isOn(agreement(99, wrong: 0)))
        #expect(PredictionPoweredInference.isOn(agreement(100, wrong: 0)))
        #expect(!PredictionPoweredInference.isOn(agreement(100, wrong: 10)))
    }
}

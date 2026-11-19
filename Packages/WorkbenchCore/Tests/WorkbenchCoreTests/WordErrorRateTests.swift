import Testing

@testable import WorkbenchCore

@Suite struct WordErrorRateTests {
    @Test func countsSubstitutionsDeletionsAndInsertionsOverTheReference() {
        #expect(WordErrorRate(reference: "kal tak bhej dunga", transcript: "kal tak bhej dunga").errors == 0)
        #expect(WordErrorRate(reference: "kal tak bhej dunga", transcript: "kal tak bej dunga").errors == 1)
        #expect(WordErrorRate(reference: "kal tak bhej dunga", transcript: "kal bhej dunga").errors == 1)
        #expect(WordErrorRate(reference: "kal tak bhej dunga", transcript: "haan kal tak bhej dunga").errors == 1)
        #expect(WordErrorRate(reference: "the deck", transcript: "").rate == 1)
        #expect(WordErrorRate(reference: "a b c d", transcript: "a x c").rate == 0.5)
    }

    @Test func caseAndPunctuationDoNotCountAndPoolingWeighsByWords() {
        #expect(WordErrorRate(reference: "Okay, send the deck.", transcript: "okay send the deck").errors == 0)
        #expect(
            WordErrorRate(reference: "don't wait", transcript: "dont wait").errors == 1,
            "an apostrophe is part of a word")
        let pooled = WordErrorRate.pooled([
            WordErrorRate(errors: 1, referenceWords: 10), WordErrorRate(errors: 3, referenceWords: 10),
        ])
        #expect(pooled.rate == 0.2)
    }
}

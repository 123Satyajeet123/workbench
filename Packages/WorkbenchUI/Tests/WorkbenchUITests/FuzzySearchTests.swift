import Testing

@testable import WorkbenchUI

struct FuzzySearchTests {
    private let groups = ["Brave Team", "Marketing", "The Brave Ones", "Family", "Café Crew"]

    private func search(_ query: String) -> [String] {
        FuzzySearch.filter(groups, by: query) { $0 }
    }

    @Test func anEmptyQueryKeepsEveryGroupInOrder() {
        #expect(search("") == groups)
        #expect(search("   ") == groups)
    }

    @Test func caseAndAccentsDoNotMatter() {
        #expect(search("BRÄVE") == ["Brave Team", "The Brave Ones"])
        #expect(search("cafe") == ["Café Crew"])
    }

    @Test func wordsMatchInAnyOrder() {
        #expect(search("team brave") == ["Brave Team"])
    }

    @Test func missingLettersStillMatch() {
        #expect(search("brv tm") == ["Brave Team"])
        #expect(search("mktg") == ["Marketing"])
    }

    @Test func oneWrongLetterInALongerWordStillMatches() {
        #expect(search("markeding") == ["Marketing"])
        #expect(search("famiky") == ["Family"])
    }

    @Test func closerMatchesComeFirst() {
        #expect(search("brave").first == "Brave Team")
        #expect(search("ones brave") == ["The Brave Ones"])
    }

    @Test func unrelatedTextMatchesNothing() {
        #expect(search("xyz").isEmpty)
        #expect(search("zz").isEmpty)
    }
}

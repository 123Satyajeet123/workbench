import Foundation
import Testing

@testable import WorkbenchCore

@Suite struct ClaimEvalTests {
    private func dev(
        _ id: String, text: String, wrong: String, right: String, quote: String, type: String = "round_size"
    )
        -> DevClaim
    {
        DevClaim(
            id: id, company: "Acme", claimType: type, claimText: text, plantedWrongValue: wrong, trueValue: right,
            truthSourceUrl: "https://news.example/\(id)", truthQuote: quote)
    }

    private var set: [DevClaim] {
        [
            dev(
                "a", text: "Acme raised $20 million.", wrong: "$20 million", right: "$11 million",
                quote: "raised $11 Mn in seed"),
            dev(
                "b", text: "Acme was founded in 2019.", wrong: "2019", right: "2022", quote: "founded in 2022",
                type: "incorporation_year"),
            dev(
                "c", text: "Acme is based in Pune.", wrong: "Pune", right: "Bengaluru", quote: "based in Bengaluru",
                type: "city"),
            dev("d", text: "Acme has one founder.", wrong: "1 founder", right: "3 founders", quote: "three founders"),
        ]
    }

    @Test func plantedWrongValuesAreCaughtTrueOnesPassAndSkipsAreSaid() {
        let built = ClaimEval.cases(from: set) { $0.id == "d" ? nil : $0.truthQuote }
        #expect(built.skipped.contains { $0.hasPrefix("d:") } && built.cases.count == 6)
        let report = ClaimEval.run(built.cases, judge: LexicalJudge.judge)
        #expect(report.planted == 3 && report.plantedContradicted == 2 && report.plantedSupported == 0)
        #expect(report.trueClaims == 3 && report.trueSupported == 3 && report.trueContradicted == 0)
    }

    @Test func aJudgeQuoteNotInThePageNeverCountsAsCaught() {
        let built = ClaimEval.cases(from: set) { $0.truthQuote }
        let report = ClaimEval.run(built.cases) { _, _ in (.contradicted, 1, "words the page does not have") }
        #expect(report.plantedContradicted == 0 && report.trueContradicted == 0)
    }

    @Test func htmlBecomesVisibleText() {
        let html =
            "<html><style>p{}</style><script>var x=1</script><p>Raised&nbsp;&#36;11 Mn</p><!-- c --><b>seed</b></html>"
        #expect(HTMLText.plain(html) == "Raised $11 Mn seed")
    }
}

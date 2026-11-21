import CryptoKit
import Foundation
import WorkbenchCore

// Offline claim eval over the dev set. Usage: claim-eval <dev folder holding claims.json and cache/>.
// No network, no model. Every number is dev, never held-out.
guard CommandLine.arguments.count == 2 else {
    print("usage: claim-eval <dev folder>")
    exit(2)
}
let folder = URL(filePath: CommandLine.arguments[1])
let claims = try JSONDecoder().decode([DevClaim].self, from: Data(contentsOf: folder.appending(path: "claims.json")))

/// The cached page of the truth source when the fixture holds it, else the truth quote alone.
func pageText(_ claim: DevClaim) -> (text: String, whole: Bool) {
    let name = Insecure.SHA1.hash(data: Data(claim.truthSourceUrl.utf8)).map { String(format: "%02x", $0) }.joined()
    guard let data = try? Data(contentsOf: folder.appending(path: "cache/\(name).txt")),
        let saved = try? JSONDecoder().decode([String: JSONValue].self, from: data),
        let body = saved["body"]?.string
    else { return (claim.truthQuote, false) }
    return (HTMLText.plain(body), true)
}

let (cases, skipped) = ClaimEval.cases(from: claims) { pageText($0).text }
let wholePages = claims.filter { pageText($0).whole }.count
let report = ClaimEval.run(cases, judge: LexicalJudge.judge)

func percent(_ part: Int, _ whole: Int) -> String {
    whole == 0 ? "n/a" : String(format: "%.0f%% (%d of %d)", 100 * Double(part) / Double(whole), part, whole)
}
print(
    "dev, offline, lexical judge (no model). Truth text: \(wholePages) cached pages, \(claims.count - wholePages) quote only."
)
print("dev: planted wrong values caught as contradicted: \(percent(report.plantedContradicted, report.planted))")
print("dev: planted wrong values wrongly supported: \(percent(report.plantedSupported, report.planted))")
print("dev: false alarm on true claims (called contradicted): \(percent(report.trueContradicted, report.trueClaims))")
print("dev: true claims supported: \(percent(report.trueSupported, report.trueClaims))")
for line in skipped { print("skipped: \(line)") }

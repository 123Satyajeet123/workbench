import Foundation
import WorkbenchCore

// Offline outbound eval. Usage: outbound-eval <fixture.json>. No network and no model: each page is answered from the
// candidates saved in the fixture. The numbers carry the fixture's own label, dev or held-out.
guard CommandLine.arguments.count == 2 else {
    print("usage: outbound-eval <fixture.json>")
    exit(2)
}
let fixture = try JSONDecoder().decode(
    OutboundFixture.self, from: Data(contentsOf: URL(filePath: CommandLine.arguments[1])))
let scratch = FileManager.default.temporaryDirectory.appending(path: "outbound-eval-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }
let report = try await OutboundEval.run(fixture, model: ReplayModel(fixture.saved), store: Store(directory: scratch))

func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", 100 * $0) } ?? "n/a" }
print("\(report.label), offline, saved replies (no model, no network). \(report.candidates) candidates.")
print(
    "\(report.label): recall in the top \(OutboundEval.recallDepth): \(percent(report.recall)) (\(report.acceptedFound) of \(report.accepted) accepted)"
)
print(
    "\(report.label): precision of the top \(report.topCount): \(percent(report.precision)) (right \(report.topRight), wrong \(report.topWrong), no call \(report.topUnmarked))"
)
let perLead = report.costPerAcceptedLead.map { String(format: "%.2f USD", $0) } ?? "n/a"
print(
    "\(report.label): estimated cost \(String(format: "%.2f", report.cost.totalUSD)) USD, per accepted lead \(perLead)")

import Foundation
import Testing

@testable import WorkbenchCore

struct ModelInputTextTests {
    private func item(_ id: Int64, _ state: Mark) -> Item {
        Item(
            id: id, task: "team.ledger", day: WorkDay(containing: Date(timeIntervalSince1970: 0)), scope: "",
            source: .whatsapp, citeFirst: id, citeLast: id, start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 0),
            fields: ["person": "Asha", "project": "Deck", "kind": "blocker", "text": "Waiting on legal", "when": ""],
            quote: "legal has it", state: state, run: RunID(1))
    }

    private let line =
        "person=Asha project=Deck kind=blocker text=Waiting on legal when= stance= asks= — \"legal has it\""

    @Test func examplesAndTrainingItemsReadTheSameAsTheModelHasAlwaysSeenThem() {
        let marked = [item(1, .confirmed), item(2, .rejected)]
        #expect(
            HelperReader.examples(marked, spec: .team, profile: .continuity)
                == "Examples the founder marked on other days:\n- right: \(line)\n- wrong: \(line)\n\n")
        #expect(
            Improver.input(spec: .team, marked: marked).hasSuffix("Marked items:\n[1] right \(line)\n[2] wrong \(line)")
        )
        let source = CitedSource(machine: "Pip", fields: ["person", "kind", "when"], item: item(3, .proposed))
        #expect(source.line == "[3] Pip · person=Asha kind=blocker — \"legal has it\" — unmarked")
    }
}

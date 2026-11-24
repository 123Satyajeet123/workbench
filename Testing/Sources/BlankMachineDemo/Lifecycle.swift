import EditorHarness
import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

/// What the person does to a blank machine after it reads: Today lists its facts, then rename, pause, delete.
@MainActor
enum Lifecycle {
    static func run(_ machines: [HelperModel], in scratch: Scratch) throws {
        heading("6. Today shows the facts of a blank machine")
        let today = scratch.today()
        let listed = machines.filter { $0.spec.listsFacts }
        let names = Set(listed.map(\.name))
        print("  Today's sections: \(today.readings.map { "\($0.name): \($0.facts.count) facts" })")
        check(
            "the screen machine is read on the Timeline page, so Today does not list it",
            scratch.crew.screenReaders.count == 1 && listed.count == machines.count - 1)
        check(
            "Today lists three facts under the name of each other machine",
            Set(today.readings.map(\.name)) == names && today.readings.allSatisfy { $0.facts.count == 3 })
        check(
            "each fact shows its own field as its title",
            today.readings.flatMap(\.facts).allSatisfy {
                !today.title(of: $0).isEmpty && today.title(of: $0) == $0["text"]
            })
        check("the empty-day message is gone", !today.isEmpty)

        heading("7. Rename, pause and delete")
        guard let first = machines.first else { throw DemoFailure("no machine") }
        let specBefore = first.spec
        scratch.crew.rename(first, to: "Renamed Example")
        check("a rename changes the name only", first.name == "Renamed Example" && first.spec == specBefore)
        scratch.crew.setPaused(first, true)
        let kept = try scratch.store.queries.items(of: first.spec.task, on: WorkDay(containing: Date())).count
        check("a pause keeps the spec and the facts", first.isPaused && first.spec == specBefore && kept == 3)
        scratch.crew.setPaused(first, false)
        check("a resume restarts it", !first.isPaused)
        for helper in scratch.crew.machines { scratch.crew.delete(helper) }
        check("after the delete the store holds no machine", try scratch.store.queries.machines().isEmpty)
        check(
            "a deleted machine's facts are gone",
            try machines.allSatisfy {
                try scratch.store.queries.items(of: $0.spec.task, on: WorkDay(containing: Date())).isEmpty
            })
    }
}

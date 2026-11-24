import EditorHarness
import Foundation

@testable import WorkbenchCore

/// `HelperSpec.problems` and the store's refusal, in both directions: every spec that ships is coherent, a spec
/// built from a source and a job is coherent, and a spec that names what it has not is refused at the store.
@MainActor
enum Rules {
    static func run(in scratch: Scratch) throws {
        heading("3. A spec that does not hold together is refused; one that does is kept")
        let shipped = MachineTemplate.all.map(\.spec) + HelperSpec.withoutMachine.map(\.spec)
        let failing = shipped.filter { !$0.problems.isEmpty }
        print("  built-in specs with a problem: \(failing.map { "\($0.task): \($0.problems)" })")
        check(
            "every built-in spec but the news pipeline's holds together",
            failing.map(\.task) == [HelperSpec.newsSignals.task])
        check("a blank job has no spec", HelperSpec(blankOver: .whatsAppChat, job: "  \n") == nil)
        guard let good = HelperSpec(blankOver: .whatsAppChat, job: Specs.job) else {
            throw DemoFailure("no blank spec")
        }
        check("the blank spec holds together", good.problems.isEmpty)

        let broken: [(String, (inout HelperSpec) -> Void)] = [
            ("the title is not a field", { $0.title = "headline" }),
            ("a badge is not a field", { $0.badges = ["owner"] }),
            ("a tone names no value", { $0.tones = ["late": .bad] }),
            (
                "a lifecycle names a field with no fixed values",
                { $0.lifecycle = .init(field: "text", open: ["a"], outcomes: ["b"]) }
            ),
            (
                "a nudge needs a member field the spec lacks",
                { $0.nudge = .init(field: "person", expected: "members", message: "No update from") }
            ),
            ("the view needs a field the spec lacks", { $0.view = .board(groupBy: "person", expected: "members") }),
            ("two fields have one name", { $0.fields.append($0.fields[0]) }),
            ("the brief is empty", { $0.brief = " " }),
        ]
        for (what, damage) in broken {
            var spec = good
            damage(&spec)
            let refusedAtCreation =
                (try? scratch.store.createMachine(withoutTemplate: spec, name: "Broken Example")) == nil
            check(
                "\(what): problems \(spec.problems.count), refused at creation: \(refusedAtCreation)",
                !spec.problems.isEmpty && refusedAtCreation)
        }
        let machine = try scratch.store.createMachine(withoutTemplate: good, name: "Edited Example")
        var damaged = machine.spec
        damaged.title = "headline"
        let refusedEdit = (try? scratch.store.change(machine, name: machine.name, spec: damaged, state: .active)) == nil
        check("a change that breaks the spec is refused as an edit too", refusedEdit)
        try scratch.store.rename(machine, to: "Renamed Example")
        try scratch.store.edit(machine, job: "A new job sentence.")
        check("a rename and a new job sentence are still accepted", true)
        try scratch.store.setState(machine, .deleted)
    }
}

import EditorHarness
import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

/// A blank machine over each offered source: the machine as the store holds it, and its spec printed.
@MainActor
enum Specs {
    static let job = "Keep what each customer asks for and when it is due."

    static func makeOverEachSource(in scratch: Scratch) throws -> [HelperModel] {
        heading("2. A blank machine over each offered source")
        var machines: [HelperModel] = []
        for source in Crew.blankMachineSources {
            guard let id = scratch.crew.createBlank(over: source, job: job, name: "\(source.name) job Example") else {
                throw DemoFailure("no machine over \(source.name): \(scratch.crew.problem ?? "no reason")")
            }
            guard let helper = scratch.crew.helper(id: id) else { throw DemoFailure("no helper for \(id)") }
            machines.append(helper)
        }
        let builtInTasks = Set(MachineTemplate.all.map(\.spec.task) + HelperSpec.withoutMachine.map(\.spec.task))
        check("no problem was shown", scratch.crew.problem == nil)
        check(
            "each machine has its own task, never a built-in's",
            Set(machines.map(\.spec.task)).count == machines.count
                && machines.allSatisfy { !builtInTasks.contains($0.spec.task) && $0.spec.task.hasPrefix("machine-") })
        check("no machine has a template", machines.allSatisfy { $0.machine.template == nil })
        check(
            "each spec holds together (HelperSpec.problems is empty)", machines.allSatisfy { $0.spec.problems.isEmpty })
        check("the page of each machine stands among the roots", machines.allSatisfy { $0.machine.folder == nil })
        check("the job is the person's sentence", machines.allSatisfy { $0.machine.job == job })
        check(
            "no lifecycle, criteria, nudge, follows, feeds or claim types",
            machines.allSatisfy {
                let spec = $0.spec
                return spec.lifecycle == nil && spec.criteria == nil && spec.nudge == nil && spec.follows == nil
                    && spec.feeds == nil && spec.claimTypes == nil
            })
        check(
            "its roles are the plain ones: it keeps no facts open and follows no machine",
            machines.allSatisfy {
                !$0.spec.keepsFacts && !$0.spec.needsFollowed && !$0.spec.rates && !$0.spec.checksClaims
            })
        if let first = machines.first { print(describe(first.spec)) }
        return machines
    }

    static func describe(_ spec: HelperSpec) -> String {
        let fields = spec.fields.map { "\($0.name) \($0.kind) — \($0.meaning)" }.joined(separator: "; ")
        return """
              the spec of \(spec.source.name):
                task: \(spec.task)    source: \(spec.source.key)    citation: \(spec.citation.rawValue)
                fields: \(fields)
                title: \(spec.title)    view: \(spec.view)    noun: \(spec.itemsNoun)    badges: \(spec.badges)    tones: \(spec.tones)
                lifecycle: \(String(describing: spec.lifecycle))    criteria: \(String(describing: spec.criteria))    nudge: \(String(describing: spec.nudge))    follows: \(String(describing: spec.follows))
                brief: \(spec.brief.replacingOccurrences(of: "\n", with: "\n                       "))
            """
    }
}

import Foundation
import WorkbenchCore

struct VersionAlarm {
    let store: Store
    let notifications: Notifications
    let problems: ProblemSlot

    func check(_ helper: HelperModel, revert: (HelperModel, HelperModel.Version) -> Void) {
        guard let decisions = try? store.queries.decisions(of: helper.spec.task) else { return }
        guard let switched = decisions.first, switched.kind == .promote,
            HelperModel.Version(decision: switched) == HelperModel.Version(helper.spec),
            let answers = try? store.queries.auditAnswers(of: helper.spec.task, since: switched.at)
        else { return warnOfDrift(helper, since: decisions.first { $0.kind != .trial }?.at ?? .distantPast) }
        let wrong = heldOutWrong(answers)
        let evidence = EProcess.alarm(wrong)
        guard evidence >= 1 / EProcess.level else { return }
        let line =
            "Back to \(helper.name)'s earlier brief: the new one was wrong on \(wrong.filter { $0 }.count) of \(wrong.count) checked items."
        revert(helper, HelperModel.Version(parentOf: switched))
        problems.attempt("log the rollback") {
            try store.log(
                Decision(
                    at: store.clock(), task: helper.spec.task, kind: .rollback, by: .alarm, brief: switched.parentBrief,
                    parentBrief: switched.brief,
                    detail: [
                        "wrong": String(wrong.filter { $0 }.count), "answers": String(wrong.count),
                        "evidence": String(format: "%.1f", evidence),
                    ]))
        }
        helper.improvement.notice = line
        notifications.announce(title: helper.name, body: line, page: .machine(helper.machine.id))
    }

    private func warnOfDrift(_ helper: HelperModel, since: Date) {
        guard let answers = try? store.queries.auditAnswers(of: helper.spec.task, since: since) else { return }
        let wrong = heldOutWrong(answers)
        guard EProcess.alarm(wrong) >= 1 / EProcess.level else { return }
        let key = MachineKey.drift(helper.spec.task)
        let version = [helper.spec.brief, helper.spec.examples.map(String.init) ?? "", helper.spec.runner ?? ""]
            .joined(separator: "\n")
        guard ((try? key.load(from: store)) ?? nil) != version else { return }
        problems.attempt("remember the warning") { try key.save(version, to: store) }
        let line =
            "\(helper.name) may have got worse: wrong on \(wrong.filter { $0 }.count) of \(wrong.count) checked items on the days set aside for testing. Try a change from your marks."
        helper.improvement.notice = line
        notifications.announce(title: helper.name, body: line, page: .machine(helper.machine.id))
    }

    private func heldOutWrong(_ answers: [(day: WorkDay, wrong: Bool)]) -> [Bool] {
        answers.filter { EvalSplit($0.day) == .heldOut }.map(\.wrong)
    }
}

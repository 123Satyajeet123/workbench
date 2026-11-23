import Foundation
import WorkbenchCore

/// Watches the version a founder switched to. Its held-out audit answers feed the certificate's drift alarm, one step
/// per run, against "wrong at most 10% of the time" (research 20 §6, step 6). When it fires, the machine goes back to the brief it came
/// from by itself, logs why and says so: the only change the app makes without the founder.
struct VersionAlarm {
    let store: Store
    let notifications: Notifications
    let problems: ProblemSlot

    /// Checks the machine's latest version; `revert` puts a machine back on an earlier version.
    func check(_ helper: HelperModel, revert: (HelperModel, HelperModel.Version) -> Void) {
        guard let decisions = try? store.queries.decisions(of: helper.spec.task) else { return }
        guard let switched = decisions.first, switched.kind == .promote,
            HelperModel.Version(decision: switched) == HelperModel.Version(helper.spec),
            let answers = try? store.queries.auditAnswers(of: helper.spec.task, since: switched.at)
        else { return warnOfDrift(helper, since: decisions.first { $0.kind != .trial }?.at ?? .distantPast) }
        let heldOut = heldOutAnswers(answers)
        guard let evidence = Certificate(answers: heldOut).firstAlarm else { return }
        let wrong = heldOut.filter(\.wrong).count
        let line =
            "Back to \(helper.name)'s earlier brief: the new one was wrong on \(wrong) of \(heldOut.count) checked items."
        revert(helper, HelperModel.Version(parentOf: switched))
        problems.attempt("log the rollback") {
            try store.log(
                Decision(
                    at: store.clock(), task: helper.spec.task, kind: .rollback, by: .alarm, brief: switched.parentBrief,
                    parentBrief: switched.brief,
                    detail: [
                        "wrong": String(wrong), "answers": String(heldOut.count),
                        "evidence": String(format: "%.1f", evidence),
                    ]))
        }
        helper.improvement.notice = line
        notifications.announce(title: helper.name, body: line, page: .machine(helper.machine.id))
    }

    /// The same alarm on a version that has no earlier one to return to: a model can change behind its name, or the
    /// work can change. It says so once per version and changes nothing; a trial is the founder's next step.
    private func warnOfDrift(_ helper: HelperModel, since: Date) {
        guard let answers = try? store.queries.auditAnswers(of: helper.spec.task, since: since) else { return }
        let heldOut = heldOutAnswers(answers)
        guard Certificate(answers: heldOut).firstAlarm != nil else { return }
        let key = MachineKey.drift(helper.spec.task)
        let version = [helper.spec.brief, helper.spec.examples.map(String.init) ?? "", helper.spec.runner ?? ""]
            .joined(separator: "\n")
        guard ((try? key.load(from: store)) ?? nil) != version else { return }
        problems.attempt("remember the warning") { try key.save(version, to: store) }
        let line =
            "\(helper.name) may have got worse: wrong on \(heldOut.filter(\.wrong).count) of \(heldOut.count) checked items on the days set aside for testing. Try a change from your marks."
        helper.improvement.notice = line
        notifications.announce(title: helper.name, body: line, page: .machine(helper.machine.id))
    }

    private func heldOutAnswers(_ answers: [(day: WorkDay, answer: Certificate.Answer)]) -> [Certificate.Answer] {
        answers.filter { EvalSplit($0.day) == .heldOut }.map(\.answer)
    }
}

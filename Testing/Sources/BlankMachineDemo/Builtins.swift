import EditorHarness
import Foundation

@testable import WorkbenchCore

/// Machines that come from a template behave as before, and a machine whose template this build lacks starts a page
/// now, as a blank one does.
@MainActor
enum Builtins {
    static func run(in scratch: Scratch) throws {
        heading("10. Built-in machines and an unknown template")
        guard let pip = GalleryTemplate.of(id: MachineTemplate.team.id),
            let machine = try scratch.store.start(pip, name: "Pip Example").machine
        else {
            throw DemoFailure("no Pip")
        }
        let titles = try Pages.firstForm(of: machine, in: scratch.store, owner: scratch.owner).map { $0.title }
        check(
            "a machine of a template starts with its first form: \(titles)",
            titles == ["Needs you", "By person", "By project"])
        check(
            "it keeps its template and its job from it",
            machine.template == MachineTemplate.team.id && machine.job == pip.job)
        let gone = try scratch.store.createMachine(from: .team, template: "gone.template.v1", name: "Gone Example")
        let goneTitles = try Pages.firstForm(of: gone, in: scratch.store, owner: scratch.owner).map { $0.title }
        check("a machine of a template this build lacks starts a page too: \(goneTitles)", !goneTitles.isEmpty)
        let blank = try scratch.store.createMachine(
            withoutTemplate: HelperSpec(blankOver: .gmailMail, job: Specs.job)!, name: "Blank Example")
        let edited = try scratch.store.queries.machines().first { $0.id == blank.id }
        try scratch.store.edit(blank, brief: "My own brief for this job.")
        let kept = try scratch.store.queries.machines().first { $0.id == blank.id }
        check(
            "a brief the person wrote stays: nothing replaces a machine's design",
            kept?.spec.brief == "My own brief for this job." && edited?.spec.fields == kept?.spec.fields)
    }
}

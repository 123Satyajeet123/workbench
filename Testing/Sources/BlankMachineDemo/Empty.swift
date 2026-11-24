import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

/// The workbench with no machine and no folder is a state the app works in: its models read it, and it says how to
/// begin.
@MainActor
enum Empty {
    static func check(_ scratch: Scratch, _ title: String) throws {
        heading(title)
        let workspace = WorkspaceModel(store: scratch.store)
        print("  the roots of the workspace: \(workspace.roots.map(\.name))")
        for root in workspace.roots { workspace.archive(root.id) }
        let today = scratch.today()
        BlankMachineDemo.check("the store holds no machine", try scratch.store.queries.machines().isEmpty)
        BlankMachineDemo.check(
            "the crew holds no machine and shows no problem",
            scratch.crew.machines.isEmpty && scratch.crew.problem == nil)
        BlankMachineDemo.check(
            "the sidebar's tree has no root, so it shows the row that adds the first machine", workspace.roots.isEmpty)
        BlankMachineDemo.check(
            "the home is empty, with no problem", today.isEmpty && today.problem == nil && today.readings.isEmpty)
        BlankMachineDemo.check("the add sheet has a source to offer", !Crew.blankMachineSources.isEmpty)
    }
}

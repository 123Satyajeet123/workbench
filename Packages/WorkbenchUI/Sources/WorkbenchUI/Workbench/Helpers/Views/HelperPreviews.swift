import SwiftUI
import WorkbenchCore

private struct MachinePagePreview: View {
    let machine: (Crew) -> HelperModel?
    private let launch = AppLaunch.start(
        storeFolder: FileManager.default.temporaryDirectory.appending(path: "workbench-preview-\(UUID().uuidString)"))

    var body: some View {
        switch launch {
        case .ready(let session):
            if let model = machine(session.crew) {
                ScrollView { HelperPage(model: model).padding() }
                    .environment(session)
                    .frame(width: 680, height: 560)
            } else {
                Text("No such machine in the scratch store")
            }
        case .failed(let failure):
            Text(failure.cause)
        }
    }
}

#Preview("Timeline machine") {
    MachinePagePreview { $0.timeline }
}

#Preview("Team machine, no group chosen") {
    MachinePagePreview { crew in crew.crew.first { $0.spec.task == HelperSpec.team.task } }
}

#Preview("Page machine, no sites named") {
    MachinePagePreview { crew in
        crew.create(from: .pages, name: "Scout").flatMap(crew.helper(id:))
    }
}

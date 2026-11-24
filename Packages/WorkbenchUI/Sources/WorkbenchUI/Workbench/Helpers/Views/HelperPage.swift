import SwiftUI
import WorkbenchCore

/// A machine's page is its document and nothing else: no header, no fold, no button row around it.
struct HelperPage: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        DocumentPage {
            if let page = model.pageModel {
                MachinePageView(model: page)
                    .onAppear {
                        page.edits = PageEdits(
                            rename: { name in
                                crew.rename(model, to: name)
                                workspace.refresh()
                            },
                            setJob: { crew.setJob(model, to: $0) },
                            setPaused: { crew.setPaused(model, $0) })
                        model.reload()
                    }
            } else if let problem = model.pageProblem {
                Text(problem).textStyle(.body)
            }
        }
    }
}

extension HelperModel {
    /// The chats or sites the founder chose, in words. Nil for the screen and for a source with nothing chosen.
    var chosenSource: String? { source.chosenSummary }
    var reads: String { source.reads }
}

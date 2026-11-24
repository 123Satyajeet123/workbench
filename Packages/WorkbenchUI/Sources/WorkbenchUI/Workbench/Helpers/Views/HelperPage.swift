import SwiftUI
import WorkbenchCore

struct HelperPage: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew
    @Environment(WorkspaceModel.self) private var workspace

    var body: some View {
        Page(
            title: model.name, subtitle: subtitle, look: model.pageModel == nil ? .of(model.machine) : nil,
            rename: model.pageModel.map { page in
                page.renaming { name in
                    crew.rename(model, to: name)
                    workspace.refresh()
                }
            },
            accessory: { DayStepper(day: model.day, today: model.today, show: model.show) },
            content: { content })
    }

    /// A machine with a page opens on its page; everything the machine page held before stays one fold below it.
    @ViewBuilder private var content: some View {
        if let page = model.pageModel {
            VStack(alignment: .leading, spacing: Space.l) {
                MachinePageView(model: page)
                Fold(isOpen: model.isChoosingSource) {
                    HelperContent(model: model).padding(.top, Space.m)
                } label: {
                    Text("Readings and settings").text(.meta)
                }
            }
            .onAppear(perform: model.reload)
        } else {
            HelperContent(model: model)
        }
    }

    private var subtitle: String {
        model.chosenSource.map { "\(model.role) · \($0)" } ?? model.role
    }
}

extension HelperModel {
    /// The chats or sites the founder chose, in words. Nil for the screen and for a source with nothing chosen.
    var chosenSource: String? { source.chosenSummary }
    var reads: String { source.reads }
}

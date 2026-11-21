import SwiftUI
import WorkbenchCore

/// People or Projects: the facts of the last seven days grouped by person or by project, open ones first, each with
/// its actions. A fact that closes moves from Open to Earlier within its group.
struct FactGroupsPage: View {
    enum Lens {
        case people, projects

        var title: String { self == .people ? "People" : "Projects" }
        var empty: String {
            self == .people
                ? "No facts about people in the last 7 days." : "No facts about projects in the last 7 days."
        }
    }

    let lens: Lens
    @Environment(TodayModel.self) private var model

    var body: some View {
        Page(
            intro: lens == .people ? .people : .projects, title: lens.title,
            subtitle: "The last \(TodayModel.days) days, open first"
        ) {
            FactGroupsBody(groups: groups, empty: lens.empty, model: model)
        }
        .onAppear(perform: model.refresh)
    }

    private var groups: [FactGroup] { lens == .people ? model.people : model.projectGroups }
}

struct FactGroupsBody: View {
    let groups: [FactGroup]
    let empty: String
    let model: TodayModel
    @Namespace private var lines
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let problem = model.problem { ProblemBanner(text: problem, dismiss: model.dismissProblem) }
            if let undo = model.undoable { UndoBar(undo: undo, model: model) }
            if groups.isEmpty { Text(empty).foregroundStyle(.supporting) }
            ForEach(groups) { group in
                TodaySection(group.name, count: group.open.isEmpty ? nil : group.open.count) {
                    ForEach(group.open) { line($0) }
                    if !group.rest.isEmpty {
                        DisclosureGroup("Earlier · \(group.rest.count)") {
                            ForEach(group.rest) { line($0) }
                        }
                        .foregroundStyle(.supporting)
                    }
                }
            }
        }
        .animation(Motion.settle(reduceMotion: reduceMotion), value: model.revision)
    }

    private func line(_ item: Item) -> some View {
        FactLine(item: item, model: model)
            .matchedGeometryEffect(id: item.id, in: lines)
    }
}

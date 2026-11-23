import SwiftUI

/// The team's name and people. Used in setup and in Settings; the caller decides when to save.
struct TeamEditor: View {
    @Environment(TeamModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Space.m) {
            TextField("Team name", text: $model.team.name, prompt: Text("Team name"))
                .textFieldStyle(.roundedBorder)
            ForEach(Array(model.team.people.indices), id: \.self) { index in
                HStack(spacing: Space.s) {
                    TextField("Name", text: $model.team.people[index].name, prompt: Text("Name"))
                    TextField("Role", text: $model.team.people[index].role, prompt: Text("Role"))
                        .frame(maxWidth: 160)
                    if model.team.people[index].isMe {
                        Text("You").foregroundStyle(.supporting).frame(width: 60, alignment: .leading)
                    } else {
                        Button("Remove", systemImage: "minus.circle") { model.remove(at: index) }
                            .labelStyle(.iconOnly).buttonStyle(.ghost).frame(width: 60, alignment: .leading)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            Button("Add a person", systemImage: "plus") { model.addPerson() }
                .buttonStyle(.ghost)
        }
    }
}

struct TeamSettingsView: View {
    @Environment(TeamModel.self) private var model
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            TeamEditor()
            LabeledContent("Team folder") {
                HStack {
                    Text(catalog.folder?.path(percentEncoded: false) ?? "None").foregroundStyle(.supporting).lineLimit(
                        1)
                    FolderButton()
                }
            }
            if let problem = model.problem { ProblemBanner(text: problem) }
            HStack {
                Spacer()
                Button("Revert", action: model.reload)
                Button("Save", action: model.save).buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: model.reload)
    }
}

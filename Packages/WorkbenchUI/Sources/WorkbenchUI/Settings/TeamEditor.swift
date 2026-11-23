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
                        Text("You").foregroundStyle(.supporting).zoomedWidth(60, alignment: .leading)
                    } else {
                        Button("Remove", systemImage: "minus.circle") { model.remove(at: index) }
                            .labelStyle(.iconOnly).buttonStyle(.ghost).zoomedWidth(60, alignment: .leading)
                    }
                }
                .textFieldStyle(.roundedBorder)
            }
            Button("Add a person", systemImage: "plus") { model.addPerson() }
                .buttonStyle(.ghost)
        }
    }
}

/// Settings › Team: the team editor, saved by hand, and the folder the team shares through.
struct TeamSection: View {
    @Environment(TeamModel.self) private var model
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        Section("People") {
            TeamEditor()
            ProblemSlotBanner(slot: model.problems)
            HStack {
                Spacer()
                Button("Revert", action: model.reload)
                Button("Save", action: model.save).buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: model.reload)
        Section("Sharing") {
            SettingRow("Team folder", catalog.folder?.path(percentEncoded: false) ?? "None") { FolderButton() }
        }
    }
}

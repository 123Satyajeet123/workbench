import SwiftUI
import WorkbenchCore

/// What the person is and which languages their sources use. The machines' instructions are written in these words,
/// so a change is saved only on the person's act and says what it costs.
struct WorkspaceProfileRows: View {
    @Environment(IdentityModel.self) private var identity
    @State private var draft = WorkspaceProfile()
    @State private var languages = ""

    var body: some View {
        SettingRow("Your role", "What you are to your team, such as founder or partner.") {
            field("Role", text: $draft.role, prompt: "founder")
        }
        SettingRow("Your work", "The trade your judgment comes from, such as investor.") {
            field("Work", text: $draft.occupation, prompt: "investor")
        }
        SettingRow("Its field", "Where that work is done, such as venture.") {
            field("Field", text: $draft.specialty, prompt: "venture")
        }
        SettingRow("Languages", "The languages your chats and mail are written in, with commas between.") {
            field("Languages", text: $languages, prompt: "Hindi, English, Hinglish")
        }
        SettingRow("Machines read with these words", Self.cost) {
            Button("Save") { identity.saveWorkspace(edited) }.disabled(edited == identity.workspace)
        }
        .onAppear(perform: load)
        .onChange(of: identity.workspace) { load() }
    }

    static let cost = "Saving changes every machine's instructions, so each machine earns its trust again."

    private var edited: WorkspaceProfile {
        var profile = draft
        profile.role = profile.role.trimmingCharacters(in: .whitespaces)
        profile.occupation = profile.occupation.trimmingCharacters(in: .whitespaces)
        profile.specialty = profile.specialty.trimmingCharacters(in: .whitespaces)
        profile.languages = languages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return profile
    }

    private func load() {
        draft = identity.workspace
        languages = identity.workspace.languages.joined(separator: ", ")
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        TextField(title, text: text, prompt: Text(prompt)).textFieldStyle(.roundedBorder).labelsHidden()
            .frame(maxWidth: 220)
    }
}

import AgentCLI
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(IdentityModel.self) private var identityModel
    @Environment(ModelSettings.self) private var models

    var body: some View {
        @Bindable var identityModel = identityModel
        @Bindable var models = models
        Form {
            Section {
                TextField("Name", text: $identityModel.identity.name)
            } header: {
                Text("You")
            } footer: {
                if let error = identityModel.saveError {
                    FormNote("Your name was not saved: \(error.localizedDescription)")
                }
            }
            Section {
                Picker("Read with", selection: $models.choice) {
                    ForEach(ModelChoice.choices) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Model")
            } footer: {
                FormNote(
                    "Runs through the claude or codex command on this Mac, with your own plan. The Runs page shows what each one costs and how often you marked its entries right."
                )
                if let tool = models.choice.kind.installed() {
                    FormNote("Uses \(tool.path(percentEncoded: false)).")
                } else {
                    FormNote("\(models.choice.kind.rawValue) is not installed on this Mac. Install it and sign in.")
                }
            }
            Section("Startup") {
                LoginItemToggle()
            }
        }
        .formStyle(.grouped)
    }
}

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
                if models.choice.kind == .claude {
                    Picker("Bill to", selection: $models.billing) {
                        ForEach(Billing.allCases) { Text($0.title).tag($0) }
                    }
                    if models.billing == .apiKey { APIKeyField() }
                }
            } header: {
                Text("Model")
            } footer: {
                FormNote(
                    "Runs through the claude or codex command on this Mac, with your own plan. Settings › Advanced shows what each one costs and how often you marked its entries right."
                )
                if let tool = models.choice.kind.installed() {
                    FormNote("Uses \(tool.path(percentEncoded: false)).")
                } else {
                    FormNote("\(models.choice.kind.rawValue) is not installed on this Mac. Install it and sign in.")
                }
            }
            RemindersSection()
            Section("Startup") {
                LoginItemToggle()
            }
        }
        .formStyle(.grouped)
    }
}

private struct APIKeyField: View {
    @Environment(ModelSettings.self) private var models
    @State private var typed = ""

    var body: some View {
        if models.hasAPIKey {
            HStack {
                Label("Your API key is saved in the Keychain.", systemImage: "key")
                Button("Remove", action: models.removeAPIKey)
            }
        } else {
            HStack {
                SecureField("Anthropic API key", text: $typed)
                Button("Save") {
                    models.saveAPIKey(typed)
                    typed = ""
                }
                .disabled(typed.isEmpty)
            }
            FormNote("Calls are billed to this key by Anthropic. It stays in this Mac's Keychain.")
        }
        if let problem = models.problem { FormNote(problem) }
    }
}

import AgentCLI
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(IdentityModel.self) private var identityModel
    @Environment(ModelSettings.self) private var models
    @Environment(CaptureSettings.self) private var capture
    @Environment(Crew.self) private var crew
    @AppStorage(AppTheme.key) private var theme = AppTheme.system

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
                if models.choice.kind == .codex || models.billing == .plan {
                    ModelReaderRows(store: models.store, kind: models.choice.kind)
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
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            RemindersSection()
            Section("Startup") {
                LoginItemToggle()
            }
            ProfileSection(
                profile: capture.profile, reading: crew.machines.filter { $0.phase == .reading }.map(\.name))
        }
        .formStyle(.grouped)
        .onChange(of: theme) { _, theme in theme.apply() }
    }
}

/// The one way into the demo, and the one way back. Switching restarts the app and changes no data.
struct ProfileSection: View {
    let profile: Profile
    let reading: [String]

    private var target: Profile { profile.isDemo ? .yours : .demo }

    var body: some View {
        Section {
            Button(ProfileSwitch.title(to: target)) { ProfileSwitch.go(to: target) }
                .disabled(target.isDemo && !ProfileSwitch.demoIsBuilt)
        } header: {
            Text(profile.isDemo ? ProfileSwitch.bannerText : "Demo")
        } footer: {
            FormNote(
                target.isDemo && !ProfileSwitch.demoIsBuilt
                    ? "The demo is not on this Mac yet." : ProfileSwitch.sentence(to: target))
            if let warning = ProfileSwitch.readingWarning(machines: reading) { FormNote(warning) }
        }
    }
}

/// The founder's own Anthropic API key: typed once, kept in the Keychain, never shown again.
private struct APIKeyField: View {
    @Environment(ModelSettings.self) private var models
    @AppStorage(AppTheme.key) private var theme = AppTheme.system
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

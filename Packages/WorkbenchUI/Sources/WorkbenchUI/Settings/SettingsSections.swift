import AgentCLI
import SwiftUI

struct SettingsSectionView: View {
    let section: SettingsSection
    @Environment(IdentityModel.self) private var identityModel
    @Environment(ModelSettings.self) private var models
    @Environment(CaptureSettings.self) private var capture
    @AppStorage(AppTheme.key) private var theme = AppTheme.system

    var body: some View {
        Form {
            switch section {
            case .general:
                you
                model
            case .appearance: appearance
            case .notch: IslandSection()
            case .notifications: RemindersSection()
            case .capture:
                sources
                DenyListSection()
                keptToday
            case .webResearch: WebResearchSection()
            case .startup: Section { LoginItemToggle() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: theme) { _, theme in theme.apply() }
        .onAppear { if section == .capture { capture.refreshLog() } }
    }

    @ViewBuilder private var you: some View {
        @Bindable var identityModel = identityModel
        Section("You") {
            SettingRow("Name", "Machines call you this in chats, as “\(founderLabel(identityModel.identity.name))”.") {
                TextField("Name", text: $identityModel.identity.name, prompt: Text("Your name"))
                    .textFieldStyle(.roundedBorder).labelsHidden().frame(maxWidth: 220)
            }
            if let error = identityModel.saveError {
                FormNote("Your name was not saved: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder private var model: some View {
        @Bindable var models = models
        Section {
            SettingRow("Read with", "The model that reads your chats and pages.") {
                Picker("Read with", selection: $models.choice) {
                    ForEach(ModelChoice.choices) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            if models.choice.kind == .claude {
                SettingRow("Bill to", "Your Claude plan, or your own Anthropic API key, billed per call.") {
                    Picker("Bill to", selection: $models.billing) {
                        ForEach(Billing.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                if models.billing == .apiKey { APIKeyField() }
            }
        } header: {
            Text("Model")
        } footer: {
            if let tool = models.choice.kind.installed() {
                FormNote("Runs through \(tool.path(percentEncoded: false)). The Usage page shows what each call costs.")
            } else {
                FormNote("\(models.choice.kind.rawValue) is not installed on this Mac. Install it and sign in.")
            }
        }
    }

    private var appearance: some View {
        Section {
            SettingRow("Theme", "Light, dark, or follow your Mac.") {
                Picker("Theme", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
        }
    }

    private var sources: some View {
        Section {
            SourceToggles()
        } header: {
            Text("Sources")
        } footer: {
            FormNote(
                capture.backgroundProblem ?? capture.failure?.localizedDescription
                    ?? "Everything stays on this Mac and is deleted after 30 days. Workbench never makes a sound.")
        }
    }

    private var keptToday: some View {
        Section("Kept today") {
            if capture.log.isEmpty { Text("Nothing yet.").foregroundStyle(.supporting) }
            ForEach(capture.log) { entry in
                LabeledContent {
                    Button("Delete", systemImage: "trash") { capture.delete(entry) }
                        .labelStyle(.iconOnly).buttonStyle(.ghost)
                } label: {
                    Label(entry.summary, systemImage: entry.symbol)
                    Text(entry.time.formatted(date: .omitted, time: .shortened))
                }
            }
        }
    }
}

private struct IslandSection: View {
    @AppStorage(IslandKey.recording) private var showsRecording = true
    @AppStorage(IslandKey.reading) private var showsReading = true
    @AppStorage(IslandKey.needsYou) private var showsNeedsYou = true
    @AppStorage(IslandKey.idle) private var idle = IslandIdle.nothing

    var body: some View {
        Section("Show") {
            SettingRow("Recording a call", "A red dot and the time. Hover for Stop.") {
                Toggle("Recording a call", isOn: $showsRecording).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("A machine reading", "Which machine is reading your chats.") {
                Toggle("A machine reading", isOn: $showsReading).labelsHidden().toggleStyle(.switch)
            }
            SettingRow("What needs you", "How many lines on Today need you, and from which machine.") {
                Toggle("What needs you", isOn: $showsNeedsYou).labelsHidden().toggleStyle(.switch)
            }
        }
        Section("Idle") {
            SettingRow("When nothing is happening", "The ring shows your Claude plan's 5-hour use.") {
                Picker("When nothing is happening", selection: $idle) {
                    ForEach(IslandIdle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    init(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        LabeledContent {
            control
        } label: {
            Text(title)
            Text(detail).foregroundStyle(.supporting)
        }
        .padding(.vertical, Space.xs)
    }
}

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

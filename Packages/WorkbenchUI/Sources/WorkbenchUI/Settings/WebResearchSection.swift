import SwiftUI
import WorkbenchCore

/// The one switch for web research, with what leaves the Mac in plain words. Off by default.
struct WebResearchSection: View {
    @Environment(CaptureSettings.self) private var capture
    @Environment(WebResearchSettings.self) private var web
    @State private var typed = ""

    var body: some View {
        @Bindable var web = web
        Section {
            Toggle(isOn: Binding(get: { capture.isOn(.web) }, set: { capture.set(.web, on: $0) })) {
                Label {
                    Text("Web research")
                    Text("Check a deal's claims against public web pages.")
                } icon: {
                    Image(systemName: "globe")
                }
            }
            .toggleStyle(.switch)
            if capture.isOn(.web) { details }
        } header: {
            Text("Web research")
        } footer: {
            FormNote(
                "When on, Workbench sends short search queries about a deal's claims to \(web.provider.title), and fetches the pages it returns. The queries name the company and the claim, for example the company name and a funding amount. Pitch decks, mail and your notes are never sent. Off, or with no key, nothing is sent. Fetched pages are kept 30 days and deleted with the rest."
            )
        }
    }

    @ViewBuilder private var details: some View {
        @Bindable var web = web
        Picker("Search provider", selection: $web.provider) {
            ForEach(SearchProviderKind.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        if web.hasKey {
            HStack {
                Label("Your \(web.provider.title) key is saved in the Keychain.", systemImage: "key")
                Button("Remove", action: web.removeKey)
            }
        } else {
            HStack {
                SecureField("\(web.provider.title) API key", text: $typed)
                Button("Save") {
                    web.saveKey(typed)
                    typed = ""
                }
                .disabled(typed.isEmpty)
            }
        }
        Picker("Queries a month", selection: $web.monthlyCap) {
            ForEach(WebResearchSettings.capChoices, id: \.self) { Text("\($0)").tag($0) }
        }
        LabeledContent("Sent this month", value: "\(web.queriesThisMonth) of \(web.monthlyCap)")
        if let problem = web.problems.text { FormNote(problem) }
    }
}

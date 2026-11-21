import SwiftUI

struct CaptureSettingsView: View {
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        Form {
            Section {
                SourceToggles()
            } header: {
                Text("Sources")
            } footer: {
                FormNote(
                    capture.backgroundProblem ?? capture.failure?.localizedDescription
                        ?? "Everything stays on this Mac and is deleted after 30 days. Workbench never makes a sound.")
            }
            WebResearchSection()
            DenyListSection()
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
        .formStyle(.grouped)
        .onAppear(perform: capture.refreshLog)
    }
}

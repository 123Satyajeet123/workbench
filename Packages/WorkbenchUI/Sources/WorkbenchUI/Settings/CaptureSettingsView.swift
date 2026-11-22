import SwiftUI
import WorkbenchCore

struct CaptureSettingsView: View {
    @Environment(CaptureSettings.self) private var capture
    @State private var confirmsWhatsAppDelete = false

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
            Section {
                LabeledContent {
                    Button("Delete…", role: .destructive) { confirmsWhatsAppDelete = true }
                } label: {
                    Label("WhatsApp messages", systemImage: "message")
                    Text(
                        "The messages Workbench kept, the facts read from them, their summaries and the model calls that read them."
                    )
                }
            } header: {
                Text("Delete")
            }
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
        .confirmationDialog("Delete all WhatsApp data?", isPresented: $confirmsWhatsAppDelete) {
            Button("Delete WhatsApp data", role: .destructive) { capture.deleteAll(.whatsapp) }
        } message: {
            Text(
                "The messages Workbench kept are deleted, with the facts read from them, your marks on those facts, their summaries and the text of the model calls that read them. Other sources stay. WhatsApp itself is not touched."
            )
        }
        .onAppear(perform: capture.refreshLog)
    }
}

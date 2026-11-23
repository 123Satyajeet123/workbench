import SwiftUI

/// Deletes every WhatsApp message Workbench kept, after one confirmation. WhatsApp itself is not touched.
struct WhatsAppDeleteSection: View {
    @Environment(CaptureSettings.self) private var capture
    @State private var confirmsDelete = false

    var body: some View {
        Section("Delete") {
            SettingRow(
                "WhatsApp messages",
                "The messages Workbench kept, the facts read from them, their summaries and the model calls that read them."
            ) {
                Button("Delete…", role: .destructive) { confirmsDelete = true }
            }
        }
        .confirmationDialog("Delete all WhatsApp data?", isPresented: $confirmsDelete) {
            Button("Delete WhatsApp data", role: .destructive) { capture.deleteAll(.whatsapp) }
        } message: {
            Text(
                "The messages Workbench kept are deleted, with the facts read from them, your marks on those facts, their summaries and the text of the model calls that read them. Other sources stay. WhatsApp itself is not touched."
            )
        }
    }
}

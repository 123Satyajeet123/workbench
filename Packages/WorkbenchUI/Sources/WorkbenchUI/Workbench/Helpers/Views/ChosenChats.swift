import LocalSources
import SwiftUI

/// The chats a machine reads now, each with a button to stop reading it. The button says what it does before it acts.
struct ChosenChats: View {
    let model: HelperModel
    let source: WhatsAppSource
    @Environment(Crew.self) private var crew
    @State private var stopping: WhatsAppChat?

    var body: some View {
        Card(title: "Chats read now", symbol: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(source.chats) { chat in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Text(chat.name).lineLimit(1)
                            Spacer()
                            Button("Stop reading") { stopping = chat }.buttonStyle(.ghost).foregroundStyle(.linkText)
                        }
                    }
                    .padding(.vertical, Space.xs)
                    if chat.id != source.chats.last?.id { Divider() }
                }
            }
        }
        .confirmationDialog(
            stopping.map { "Stop reading \($0.name)?" } ?? "", isPresented: isAsking, presenting: stopping
        ) { chat in
            Button("Stop reading and erase", role: .destructive) {
                model.attempt("stop reading the chat") { try crew.stopReading(chat) }
                model.reload()
            }
        } message: { chat in
            Text(WhatsAppSource.stopWarning(alsoStopping: crew.otherReaders(of: chat, besides: model)))
        }
    }

    private var isAsking: Binding<Bool> {
        Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } })
    }
}

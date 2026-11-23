import SwiftUI
import WorkbenchCore

struct HelperPage: View {
    let model: HelperModel

    var body: some View {
        Page(
            title: model.name, subtitle: subtitle, look: model.pageModel == nil ? .of(model.machine) : nil,
            accessory: { DayStepper(day: model.day, today: model.today, show: model.show) },
            content: { content })
    }

    /// A machine with a page opens on its page; everything the machine page held before stays one fold below it.
    @ViewBuilder private var content: some View {
        if let page = model.pageModel {
            VStack(alignment: .leading, spacing: Space.l) {
                MachinePageView(model: page)
                Fold(isOpen: model.isChoosingSource) {
                    HelperContent(model: model).padding(.top, Space.m)
                } label: {
                    Text("Readings and settings").text(.sectionTitle)
                }
            }
            .onAppear(perform: model.reload)
        } else {
            HelperContent(model: model)
        }
    }

    private var subtitle: String {
        model.chosenSource.map { "\(model.role) · \($0)" } ?? model.role
    }
}

extension HelperModel {
    /// The chats or sites the founder chose, in words. Nil for the screen and for a source with nothing chosen.
    var chosenSource: String? {
        if let source = source as? WhatsAppSource {
            if source.readsEveryChat { return "Every WhatsApp chat" }
            return source.isSeveral ? "\(source.chats.count) chats" : source.chat?.name
        }
        if let source = source as? TelegramSource, let chat = source.chat { return "Telegram · \(chat.title)" }
        if let source = source as? PageSource, !source.sites.isEmpty { return source.sites.joined(separator: ", ") }
        if let source = source as? MailSource, source.isReady {
            return "Gmail · " + source.labels.joined(separator: ", ")
        }
        return nil
    }

    var reads: String {
        chosenSource ?? (source is ScreenSource ? "Your screen windows" : "Nothing chosen yet")
    }
}

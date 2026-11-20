import SwiftUI
import WorkbenchCore

/// A machine's page: its face and name, the day, and the machine's content.
struct HelperPage: View {
    let model: HelperModel

    var body: some View {
        Page(
            title: model.name, subtitle: subtitle, look: .of(model.machine),
            accessory: { DayStepper(day: model.day, today: model.today, show: model.show) },
            content: { HelperContent(model: model) })
    }

    private var subtitle: String {
        let role = model.isPaused ? "Paused" : MachineTemplate.of(model.machine)?.role ?? ""
        return model.chosenSource.map { "\(role) · \($0)" } ?? role
    }
}

extension HelperModel {
    /// The chats or sites the founder chose, in words. Nil for the screen and for a source with nothing chosen.
    var chosenSource: String? {
        if let source = source as? WhatsAppSource {
            return source.isSeveral ? "\(source.chats.count) chats" : source.chat?.name
        }
        if let source = source as? PageSource, !source.sites.isEmpty { return source.sites.joined(separator: ", ") }
        if let source = source as? MailSource, source.isReady {
            return "Gmail · " + source.labels.joined(separator: ", ")
        }
        return nil
    }

    /// What the machine reads, for a card that says it in one line.
    var reads: String {
        chosenSource ?? (source is ScreenSource ? "Your screen windows" : "Nothing chosen yet")
    }
}

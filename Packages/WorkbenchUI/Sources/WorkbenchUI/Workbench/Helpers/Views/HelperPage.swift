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
        if let source = model.source as? WhatsAppSource {
            if source.isSeveral { return "\(role) · \(source.chats.count) chats" }
            return source.chat.map { "\(role) · \($0.name)" } ?? role
        }
        if let source = model.source as? PageSource, !source.sites.isEmpty {
            return "\(role) · \(source.sites.joined(separator: ", "))"
        }
        return role
    }
}

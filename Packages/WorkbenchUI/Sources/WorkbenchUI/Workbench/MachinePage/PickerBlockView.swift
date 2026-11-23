import SwiftUI
import WorkbenchCore

/// The chooser of one kind of source, inside the page. The person's click in it is the grant; the block holds none.
struct PickerBlockView: View {
    let model: MachinePageModel
    let kind: PickerKind

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(Self.title(of: kind)).text(.sectionTitle)
            chooser
        }
    }

    @ViewBuilder private var chooser: some View {
        let helper = model.helper
        switch kind {
        case .whatsappChats:
            if let source = helper.source as? WhatsAppSource {
                GroupChooser(model: helper, source: source)
            } else {
                unavailable("\(model.name) does not read WhatsApp.")
            }
        case .mailLabel:
            if let source = helper.source as? MailSource {
                LabelChooser(model: helper, source: source)
            } else {
                unavailable("\(model.name) does not read Gmail.")
            }
        case .sites:
            if let source = helper.source as? PageSource {
                SiteChooser(model: helper, source: source)
            } else {
                unavailable("\(model.name) does not read sites.")
            }
        case .files: unavailable("Choosing files is not available yet.")
        }
    }

    private func unavailable(_ words: String) -> some View { Text(words).text(.meta) }

    static func title(of kind: PickerKind) -> String {
        switch kind {
        case .whatsappChats: "WhatsApp chats to read"
        case .mailLabel: "Gmail label to read"
        case .sites: "Sites to read"
        case .files: "Files to read"
        }
    }
}

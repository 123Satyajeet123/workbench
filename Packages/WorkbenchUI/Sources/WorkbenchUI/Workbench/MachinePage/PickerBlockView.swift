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
        if Self.chooses(kind, for: helper.spec.source), let chooser = helper.source.chooser(for: helper) {
            chooser
        } else {
            Text(unavailable).text(.meta)
        }
    }

    private var unavailable: String {
        switch kind {
        case .whatsappChats: "\(model.name) does not read WhatsApp."
        case .mailLabel: "\(model.name) does not read Gmail."
        case .sites: "\(model.name) does not read sites."
        case .files: "Choosing files is not available yet."
        }
    }

    /// Whether this kind of picker chooses what the source reads.
    private static func chooses(_ kind: PickerKind, for source: SourceDescriptor) -> Bool {
        switch kind {
        case .whatsappChats: source.picker == .chat && source.consent == .whatsapp
        case .mailLabel: source.picker == .mailLabel
        case .sites: source.picker == .sites
        case .files: source.picker == .file
        }
    }

    static func title(of kind: PickerKind) -> String {
        switch kind {
        case .whatsappChats: "WhatsApp chats to read"
        case .mailLabel: "Gmail label to read"
        case .sites: "Sites to read"
        case .files: "Files to read"
        }
    }
}

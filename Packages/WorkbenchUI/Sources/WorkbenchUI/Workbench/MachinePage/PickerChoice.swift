import SwiftUI
import WorkbenchCore

/// What a picker block of the page stands for: choosing what one kind of source reads. The person's click in the
/// chooser is the grant; the block holds none.
enum PickerChoice {
    static func title(of kind: PickerKind) -> String {
        switch kind {
        case .whatsappChats: "WhatsApp chats to read"
        case .mailLabel: "Gmail label to read"
        case .sites: "Sites to read"
        case .files: "Files to read"
        }
    }

    /// Why this machine cannot choose with this picker, in words for the person; nil when it can.
    static func unavailableNote(_ kind: PickerKind, for helper: HelperModel) -> String? {
        guard !(chooses(kind, for: helper.spec.source) && helper.source.chooser(for: helper) != nil) else { return nil }
        switch kind {
        case .whatsappChats: return "\(helper.name) does not read WhatsApp."
        case .mailLabel: return "\(helper.name) does not read Gmail."
        case .sites: return "\(helper.name) does not read sites."
        case .files: return "Choosing files is not available yet."
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
}

/// The chooser of one kind of source, in a sheet over the page.
struct PickerSheet: View {
    let kind: PickerKind
    let helper: HelperModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(PickerChoice.title(of: kind)).text(.sectionTitle)
            if let chooser = helper.source.chooser(for: helper) { chooser }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.l)
        .frame(minWidth: 420)
    }
}

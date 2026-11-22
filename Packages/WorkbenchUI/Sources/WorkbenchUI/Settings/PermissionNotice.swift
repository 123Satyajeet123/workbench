import AppKit
import LocalSources
import SwiftUI

struct PermissionNotice: View {
    let message: String
    let pane: PrivacyPane

    var body: some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Tone.attention.color)
            Spacer()
            Button("Open System Settings") { SystemSettings.open(pane: pane) }
        }
        .textStyle(.callout)
    }
}

enum SystemSettings {
    static func open(pane: PrivacyPane) { NSWorkspace.shared.open(pane.url) }
}

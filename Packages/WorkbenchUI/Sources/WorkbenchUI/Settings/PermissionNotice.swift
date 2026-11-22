import AppKit
import SwiftUI

struct PermissionNotice: View {
    let message: String
    let pane: String

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
    static func open(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

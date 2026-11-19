import SwiftUI

struct MenuBarIcon: View {
    let capture: CaptureSettings

    var body: some View {
        if capture.call != nil {
            Image(systemName: "record.circle.fill").accessibilityLabel("Workbench, recording a call")
        } else {
            Image(systemName: capture.status.symbol)
                .accessibilityLabel("Workbench, capture \(capture.status.title.lowercased())")
        }
    }
}

import CaptureService
import LocalSources
import SwiftUI

/// Start and stop a call recording. Only apps playing sound are offered; nothing starts on its own.
struct CallMenu: View {
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        if let call = capture.call {
            Button("Stop recording \(call.app) (started \(call.startedAt.formatted(date: .omitted, time: .shortened)))")
            {
                capture.stopCall()
            }
        } else {
            let isPrivate = capture.mode == .privateHour
            Menu(isPrivate ? "Record a call anyway (private mode is on)" : "Record a call") {
                ForEach(capture.playingApps) { app in
                    Button(app.name) { capture.startCall(in: app, confirmed: isPrivate) }
                }
                if capture.playingApps.isEmpty { Text("No app is playing sound") }
                Divider()
                Button("In person (microphone only)") { capture.startCall(in: nil, confirmed: isPrivate) }
            }
        }
        if let failure = capture.failure {
            Text(failure.localizedDescription)
            if (failure as? CallStartError)?.needsCallSwitch == true {
                SettingsLink { Text("Open Settings") }
            }
            Button("Dismiss") { capture.dismissFailure() }
        }
    }
}

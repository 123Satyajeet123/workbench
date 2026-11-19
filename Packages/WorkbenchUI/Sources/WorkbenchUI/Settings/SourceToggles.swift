import AppKit
import LocalSources
import SwiftUI
import WorkbenchCore

/// The one place a capture source is switched on or off, with what macOS must allow for it.
struct SourceToggles: View {
    @Environment(CaptureSettings.self) private var capture
    @State private var microphoneRefused = false

    var body: some View {
        ForEach(CaptureSource.all) { source in
            Toggle(isOn: binding(for: source.source)) {
                Label {
                    Text(source.name)
                    Text(source.reason)
                } icon: {
                    Image(systemName: source.symbol)
                }
            }
            .toggleStyle(.switch)
            if source.source == .screen, capture.isOn(.screen), capture.status == .needsPermission {
                refusal("macOS has not given Workbench Accessibility access yet.", pane: "Privacy_Accessibility")
            }
            if source.source == .call, microphoneRefused {
                refusal("macOS refused microphone access.", pane: "Privacy_Microphone")
            }
        }
    }

    private func binding(for kind: SourceKind) -> Binding<Bool> {
        Binding {
            capture.isOn(kind)
        } set: { on in
            capture.set(kind, on: on)
            if on, kind == .screen || kind == .screenText, !ScreenReader.isTrusted { ScreenReader.requestTrust() }
            if kind == .call { askForMicrophone(on) }
        }
    }

    private func askForMicrophone(_ on: Bool) {
        microphoneRefused = false
        guard on else { return }
        Task {
            guard await !CallAudioRecorder.requestMicrophone() else { return }
            microphoneRefused = true
            capture.set(.call, on: false)
        }
    }

    private func refusal(_ message: String, pane: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Tone.attention.color)
            Spacer()
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .font(.callout)
    }
}

import LocalSources
import SwiftUI
import WorkbenchCore

/// The one place a capture source is switched on or off, with what macOS must allow for it.
struct SourceToggles: View {
    @Environment(CaptureSettings.self) private var capture
    @Environment(TodayModel.self) private var today: TodayModel?
    @State private var microphoneRefused = false
    private static let iconWidth: CGFloat = 20

    var body: some View {
        ForEach(CaptureSource.all) { source in
            Toggle(isOn: binding(for: source.source)) {
                Label {
                    Text(source.name)
                    Text(source.reason)
                } icon: {
                    Image(systemName: source.symbol).frame(width: Self.iconWidth)
                }
            }
            .toggleStyle(.switch)
            if source.source == .screen, capture.isOn(.screen), capture.status == .needsPermission {
                PermissionNotice(
                    message: "macOS has not given Workbench Accessibility access yet.", pane: "Privacy_Accessibility")
            }
            if source.source == .call, microphoneRefused {
                PermissionNotice(message: "macOS refused microphone access.", pane: "Privacy_Microphone")
            }
            if source.source == .calendar, capture.isOn(.calendar) { calendarDetails }
        }
    }

    @ViewBuilder private var calendarDetails: some View {
        if let refusal = today?.meetings.refusal {
            PermissionNotice(message: refusal, pane: "Privacy_Calendars")
        }
        CalendarChooser(calendars: capture.calendarChoices(among: today?.meetings.calendars ?? [])) {
            capture.toggle($0, among: today?.meetings.calendars ?? [])
            Task { await today?.refreshMeetings() }
        }
    }

    private func binding(for kind: SourceKind) -> Binding<Bool> {
        Binding {
            capture.isOn(kind)
        } set: { on in
            if kind == .call { microphoneRefused = false }
            capture.set(kind, on: on)
            Task {
                let allowed = await capture.askForAccess(kind, today: today)
                if kind == .call { microphoneRefused = !allowed }
            }
        }
    }
}

extension CaptureSettings {
    func askForAccess(_ kind: SourceKind, today: TodayModel?) async -> Bool {
        if kind == .calendar { await today?.refreshMeetings() }
        guard isOn(kind) else { return true }
        switch kind {
        case .screen, .screenText:
            if !ScreenReader.isTrusted { ScreenReader.requestTrust() }
        case .call:
            guard await CallAudioRecorder.requestMicrophone() else {
                set(.call, on: false)
                return false
            }
        default: break
        }
        return true
    }
}

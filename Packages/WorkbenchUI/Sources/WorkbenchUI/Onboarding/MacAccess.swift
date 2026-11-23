import AgentCLI
import LocalSources
import Observation

@Observable
final class MacAccess {
    private(set) var readerFound = false
    private(set) var screenTrusted = false
    private(set) var microphoneRefused = false
    private(set) var fullDiskAccess = false

    func recheck(reader: AgentCLIKind) {
        readerFound = reader.installed() != nil
        screenTrusted = ScreenReader.isTrusted
        microphoneRefused = CallAudioRecorder.microphoneRefused
        fullDiskAccess = FullDiskAccess.isGranted()
    }
}

extension ConnectFacts {
    init(
        access: MacAccess, capture: CaptureSettings, today: TodayModel, pip: HelperModel?, sourceRows: [ConnectRow]
    ) {
        self.init(
            readerFound: access.readerFound, screenOn: capture.isOn(.screen), screenTextOn: capture.isOn(.screenText),
            screenTrusted: access.screenTrusted,
            fullDiskAccess: access.fullDiskAccess, chats: (pip?.source as? WhatsAppSource)?.chats.map(\.name) ?? [],
            calendarOn: capture.isOn(.calendar), calendarRefused: today.meetings.refusal != nil,
            callsOn: capture.isOn(.call), microphoneRefused: access.microphoneRefused, mailOn: capture.isOn(.mail),
            webOn: capture.isOn(.web), sourceRows: sourceRows)
    }
}

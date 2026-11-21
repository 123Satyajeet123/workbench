enum ConnectRow: CaseIterable, Identifiable {
    case reader, screen, whatsApp, calendar, calls

    var id: Self { self }

    static let sources: [Self] = [.screen, .whatsApp, .calendar, .calls]
}

enum ConnectStatus: Equatable {
    case ready, off, missing
    case needsPermission(pane: String)
    case chosen(String)

    var isDone: Bool {
        switch self {
        case .ready, .chosen: true
        case .off, .missing, .needsPermission: false
        }
    }

    var title: String {
        switch self {
        case .ready: "Ready"
        case .off: "Off"
        case .missing: "Not installed"
        case .needsPermission: "Needs permission"
        case .chosen(let name): name
        }
    }
}

struct ConnectFacts: Equatable {
    var readerFound = false
    var screenOn = false
    var screenTrusted = false
    var fullDiskAccess = false
    var chats: [String] = []
    var calendarOn = false
    var calendarRefused = false
    var callsOn = false
    var microphoneRefused = false

    func status(of row: ConnectRow) -> ConnectStatus {
        switch row {
        case .reader:
            return readerFound ? .ready : .missing
        case .screen:
            guard screenOn else { return .off }
            return screenTrusted ? .ready : .needsPermission(pane: "Privacy_Accessibility")
        case .whatsApp:
            guard fullDiskAccess else { return .needsPermission(pane: "Privacy_AllFiles") }
            if let only = chats.first, chats.count == 1 { return .chosen(only) }
            return chats.isEmpty ? .off : .chosen("\(chats.count) chats")
        case .calendar:
            guard calendarOn else { return .off }
            return calendarRefused ? .needsPermission(pane: "Privacy_Calendars") : .ready
        case .calls:
            if microphoneRefused { return .needsPermission(pane: "Privacy_Microphone") }
            return callsOn ? .ready : .off
        }
    }

    var isSet: Bool {
        status(of: .reader).isDone && ConnectRow.sources.contains { status(of: $0).isDone }
    }
}

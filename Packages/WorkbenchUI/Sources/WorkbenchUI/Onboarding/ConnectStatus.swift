import LocalSources
import WorkbenchCore

enum ConnectRow: CaseIterable, Identifiable {
    case reader, screen, screenText, whatsApp, mail, web, calendar, calls

    var id: Self { self }

    static let sources: [Self] = allCases.filter { $0 != .reader }

    init?(_ kind: SourceKind) {
        guard let row = Self.allCases.first(where: { $0.kind == kind }) else { return nil }
        self = row
    }

    var kind: SourceKind? {
        switch self {
        case .reader: nil
        case .screen: .screen
        case .screenText: .screenText
        case .whatsApp: .whatsapp
        case .mail: .mail
        case .web: .web
        case .calendar: .calendar
        case .calls: .call
        }
    }

    /// What a source row is called. The reader's name depends on the model the person chose, so it has none here.
    var sourceName: String? {
        switch self {
        case .reader: nil
        case .whatsApp: "WhatsApp"
        case .web: "Web research"
        case .screen, .screenText, .mail, .calendar, .calls: CaptureSource.all.first { $0.source == kind }?.name
        }
    }

    /// The kind a "Turn on" switch sets. WhatsApp and mail are turned on on the page of their machine.
    var kindToTurnOn: SourceKind? {
        switch self {
        case .reader, .whatsApp, .mail: nil
        case .screen, .screenText, .web, .calendar, .calls: kind
        }
    }

    /// The reader, then one row for each source the machines of a team template need.
    static func rows(for needs: [SourceNeed]) -> [Self] {
        [.reader] + needs.compactMap { Self($0.kind) }
    }

    /// Pages, mail and web research are read in a browser, through the extension.
    static func needsBrowser(for needs: [SourceNeed]) -> Bool {
        needs.contains { [.screenText, .mail, .web].contains($0.kind) }
    }
}

enum ConnectStatus: Equatable {
    case ready, off, missing, waiting
    case needsPermission(pane: PrivacyPane)
    case chosen(String)

    var isDone: Bool {
        switch self {
        case .ready, .chosen: true
        case .off, .missing, .waiting, .needsPermission: false
        }
    }

    var title: String {
        switch self {
        case .ready: "Ready"
        case .off: "Off"
        case .missing: "Not installed"
        case .waiting: "Waiting for the extension"
        case .needsPermission: "Needs permission"
        case .chosen(let name): name
        }
    }
}

/// One Chromium browser on this Mac, and what the person and the extension have done with it.
struct BrowserFact: Equatable, Identifiable {
    let id: String
    let name: String
    var isEnabled: Bool
    var isConnected: Bool
}

struct ConnectFacts: Equatable {
    var readerFound = false
    var screenOn = false
    var screenTextOn = false
    var screenTrusted = false
    var fullDiskAccess = false
    var chats: [String] = []
    var calendarOn = false
    var calendarRefused = false
    var callsOn = false
    var microphoneRefused = false
    var mailOn = false
    var webOn = false
    /// The Chromium browsers installed here. The extension needs one, so a team that reads pages shows them.
    var browsers: [BrowserFact] = []
    var needsBrowser = false
    /// The rows of the sources that count toward `isSet`.
    var sourceRows = ConnectRow.sources

    func status(of row: ConnectRow) -> ConnectStatus {
        switch row {
        case .reader:
            return readerFound ? .ready : .missing
        case .screen:
            guard screenOn else { return .off }
            return screenTrusted ? .ready : .needsPermission(pane: .accessibility)
        case .screenText:
            guard screenTextOn else { return .off }
            return screenTrusted ? .ready : .needsPermission(pane: .accessibility)
        case .mail:
            return mailOn ? .ready : .off
        case .web:
            return webOn ? .ready : .off
        case .whatsApp:
            guard fullDiskAccess else { return .needsPermission(pane: .fullDiskAccess) }
            if let only = chats.first, chats.count == 1 { return .chosen(only) }
            return chats.isEmpty ? .off : .chosen("\(chats.count) chats")
        case .calendar:
            guard calendarOn else { return .off }
            return calendarRefused ? .needsPermission(pane: .calendars) : .ready
        case .calls:
            if microphoneRefused { return .needsPermission(pane: .microphone) }
            return callsOn ? .ready : .off
        }
    }

    /// Connected only when the extension has talked to the app through the native host.
    func status(of browser: BrowserFact) -> ConnectStatus {
        guard browser.isEnabled else { return .off }
        return browser.isConnected ? .ready : .waiting
    }

    var isSet: Bool {
        status(of: .reader).isDone && (sourceRows.isEmpty || sourceRows.contains { status(of: $0).isDone })
    }
}

import CaptureService
import Foundation
import LocalSources
import Observation
import WorkbenchCore

@Observable
final class CaptureSettings {
    static let alwaysPrivate =
        "password managers, the Health app, banking, health and password sites, private windows and password fields"

    private let service: CaptureService
    private let staleSites: () -> [String]
    private let installedBrowsers: () -> [InstalledBrowser]
    private let telegramKeysKnown: () -> Bool
    /// The data this app opened. Capture settings and the controls that start capture are shown only for a profile
    /// that captures.
    let profile: Profile
    private(set) var log: [CaptureLogEntry] = []
    private(set) var failure: (any Error)?
    /// What stops each source now, as last refreshed. The one place any page asks.
    private(set) var sourceHealth: [SourceHealth] = []
    @ObservationIgnored var onCallSaved: () -> Void = {}

    init(
        service: CaptureService, profile: Profile = .yours, staleSites: @escaping () -> [String] = { [] },
        installedBrowsers: @escaping () -> [InstalledBrowser] = BrowserRegistry.installedHere,
        telegramKeysKnown: @escaping () -> Bool = { TelegramAccount.keysSaved(in: KeychainSecrets()) }
    ) {
        self.telegramKeysKnown = telegramKeysKnown
        self.service = service
        self.profile = profile
        self.staleSites = staleSites
        self.installedBrowsers = installedBrowsers
        refreshLog()
        refreshHealth()
    }

    var status: CaptureStatus { service.status }

    /// Whether the sensors are being read now. False for a profile that does not capture.
    var isRunning: Bool { service.isRunning }

    var mode: CaptureMode {
        get { CaptureMode(service.policy.mode, at: .now) }
        set { change { $0.mode = newValue.policyMode(at: .now) } }
    }

    func isOn(_ kind: SourceKind) -> Bool { service.policy.isEnabled(kind) }

    func set(_ kind: SourceKind, on: Bool) { change { $0.switches[kind] = on } }

    var enabledBrowsers: Set<String> { Set(service.policy.browsers.keys) }

    func set(_ browser: ChromiumBrowser, on: Bool) {
        change { $0.browsers[browser.bundleID] = on ? browser.name : nil }
    }

    /// The calendars among `all` that Today reads: every meeting calendar until the person chooses.
    func calendarChoices(among all: [CalendarInfo]) -> [CalendarChoice] {
        let read = Set(all.read(chosen: service.policy.allowList[.calendar]).map(\.id))
        return all.map { CalendarChoice(id: $0.id, title: $0.title, isRead: read.contains($0.id)) }
    }

    /// Reads or stops reading one calendar. Choosing the meeting calendars again clears the choice.
    func toggle(_ calendar: CalendarChoice, among all: [CalendarInfo]) {
        var read = Set(calendarChoices(among: all).filter(\.isRead).map(\.id))
        if calendar.isRead { read.remove(calendar.id) } else { read.insert(calendar.id) }
        change { $0.allowList[.calendar] = read == Set(all.read(chosen: nil).map(\.id)) ? nil : read }
    }

    var denyList: [DeniedPlace] { (service.policy.denyList[.screen] ?? []).sorted().map(DeniedPlace.init(label:)) }

    var neverCaptured: String {
        ([Self.alwaysPrivate] + denyList.map(\.name)).formatted(.list(type: .and))
    }

    /// An installed app's name or a website. False when the text is neither.
    func deny(_ text: String) -> Bool {
        guard let place = DeniedPlace(typed: text) else { return false }
        change { $0.denyList[.screen, default: []].insert(place.label) }
        return true
    }

    func allow(_ place: DeniedPlace) {
        change {
            $0.denyList[.screen]?.remove(place.label)
            if $0.denyList[.screen]?.isEmpty == true { $0.denyList[.screen] = nil }
        }
    }

    var call: Recording? { service.call }

    var backgroundProblem: String? { service.problem }

    func recordings(since start: Date) -> [Recording] {
        var found: [Recording] = []
        attempt { found = try service.recordings(since: start) }
        return found
    }

    var playingApps: [AudioApp] { service.playingApps }

    func startCall(in app: AudioApp?, confirmed: Bool) {
        Task {
            do {
                try await service.startCall(in: app, confirmed: confirmed)
                failure = nil
            } catch {
                failure = error
            }
        }
    }

    func dismissFailure() { failure = nil }

    func stopCall() {
        guard service.call != nil else { return }
        attempt { try service.stopCall() }
        onCallSaved()
    }

    func refreshLog() {
        attempt { log = try service.keptToday(limit: 20).compactMap(CaptureLogEntry.init) }
    }

    func delete(_ entry: CaptureLogEntry) {
        attempt { try service.forget(entry.activity) }
        refreshLog()
    }

    func deleteAll(_ kind: SourceKind) {
        attempt { try service.forgetAll(kind) }
    }

    private func change(_ edit: (inout CapturePolicy) -> Void) {
        attempt { try service.update(edit) }
        refreshHealth()
    }

    /// Ends the open screen stretch before the app quits.
    func endForQuit() { service.endForQuit() }

    func refreshHealth() {
        let policy = service.policy
        sourceHealth = SourceHealthModel.health(
            SourceHealthInputs(
                policy: policy, fullDiskAccess: FullDiskAccess.isGranted(),
                ownerKnown: (try? service.owner()) != nil, accessibilityGranted: ScreenReader.isTrusted,
                telegramKeysKnown: telegramKeysKnown(),
                staleSites: staleSites(), browsers: installedBrowsers().map { policy.health(ofBrowser: $0.browser) }))
    }

    func health(of source: SourceHealth.Source) -> SourceHealth? { sourceHealth.first { $0.source == source } }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = error
        }
    }
}

extension CaptureStatus {
    var title: String {
        switch self {
        case .capturing: "On"
        case .paused: "Paused"
        case .privateMode: "Private"
        case .off: "Off"
        case .needsPermission: "Needs permission"
        }
    }

    var symbol: String {
        switch self {
        case .capturing: "eye"
        case .paused: "pause.circle"
        case .privateMode: "eye.slash"
        case .off: "circle.slash"
        case .needsPermission: "exclamationmark.triangle"
        }
    }
}

enum CaptureMode: CaseIterable, Identifiable {
    case on, paused, privateHour, off

    var id: Self { self }

    static let privateOrPausedFor: TimeInterval = 3600

    init(_ mode: CapturePolicy.Mode, at now: Date) {
        switch mode {
        case .on: self = .on
        case .off: self = .off
        case .paused(let until): self = now < until ? .paused : .on
        case .privateMode(let until): self = now < until ? .privateHour : .on
        }
    }

    func policyMode(at now: Date) -> CapturePolicy.Mode {
        switch self {
        case .on: .on
        case .off: .off
        case .paused: .paused(until: now.addingTimeInterval(Self.privateOrPausedFor))
        case .privateHour: .privateMode(until: now.addingTimeInterval(Self.privateOrPausedFor))
        }
    }

    var title: String {
        switch self {
        case .on: "On"
        case .paused: "Paused"
        case .privateHour: "Private for 1 hour"
        case .off: "Off"
        }
    }
}

/// A source the founder switches on in Settings. WhatsApp is switched on by choosing a group in the team helper, and Mail by naming a label in the deal helper.
struct CaptureSource: Identifiable {
    let source: SourceKind
    let name: String
    let symbol: String
    let reason: String

    var id: SourceKind { source }

    static let all = [
        CaptureSource(
            source: .screen, name: "Screen", symbol: "rectangle.dashed",
            reason: "Which app, window and page you are in. No pixels, no keystrokes."),
        CaptureSource(
            source: .screenText, name: "Screen text", symbol: "text.viewfinder",
            reason: "The text in the window you are in. Never a password field or a private window."),
        CaptureSource(
            source: .mail, name: "Mail", symbol: "envelope",
            reason: "Gmail threads you open in the label you named in a deal helper. No other mail."),
        CaptureSource(
            source: .calendar, name: "Calendar", symbol: "calendar",
            reason: "Today's meetings: title, time and who is in them. Never written to the calendar."),
        CaptureSource(
            source: .call, name: "Calls", symbol: "phone",
            reason: "Your microphone and the other side's audio, only for calls you choose to record."),
    ]
}

struct DeniedPlace: Identifiable, Equatable {
    let label: String
    let name: String

    var id: String { label }

    init(label: String) {
        self.label = label
        name = InstalledApps.name(of: label) ?? label
    }

    init?(typed text: String) {
        let text = text.trimmingCharacters(in: .whitespaces)
        if let bundleID = InstalledApps.bundleID(named: text) {
            self.init(label: bundleID)
        } else if let domain = Self.domain(text) {
            self.init(label: domain)
        } else {
            return nil
        }
    }

    static func domain(_ text: String) -> String? {
        let candidate = text.lowercased()
        guard !candidate.isEmpty, !candidate.contains(" "), candidate.contains(".") else { return nil }
        let host = URLComponents(string: candidate.contains("://") ? candidate : "https://" + candidate)?.host
        return host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
    }
}

struct CaptureLogEntry: Identifiable, Equatable {
    let activity: Activity
    let id: Int64
    let time: Date
    let symbol: String
    let summary: String

    init?(_ activity: Activity) {
        guard let id = activity.id else { return nil }
        self.activity = activity
        self.id = id
        time = activity.at
        if activity.kind == .file {
            symbol = "doc"
            summary = "\(activity.title.capitalized): \(URL(string: activity.document ?? "")?.lastPathComponent ?? "")"
        } else {
            symbol = "macwindow"
            summary = activity.title.isEmpty ? activity.app : "\(activity.app): \(activity.title)"
        }
    }
}

import AppKit
import LocalSources
import Observation
import WorkbenchCore

/// The morning list as a ritual: at the morning hour the person set, or at the first moment they are at the Mac after
/// it, one notification says how many things need them today, and a click opens Today. It never posts while the
/// screen is locked or the Mac sleeps. Silence when nothing needs the person. The notification gate decides the cap
/// and the quiet hours; when it posts nothing, the day stays open and the next wake or unlock tries again.
///
/// The schedule is event driven: it wakes at the morning hour (one sleep until the next one, not a poll), when the Mac
/// wakes, when its screen wakes and when it unlocks. Each wake runs the same check, which first fires the timers that
/// are due so slipped facts are current, then asks Today how many lines need the person.
@Observable
final class MorningSchedule {
    static let settingsKey = StateKey<MorningSettings>.json("morning")
    private static let decidedKey = StateKey<WorkDay>.day("morning.decided")
    static let unlockedEvent = Notification.Name("com.apple.screenIsUnlocked")
    /// Idle time that still counts as at the Mac for the notification: the capture loops' own limit.
    private static let idleAfter: TimeInterval = 120

    var settings = MorningSettings() {
        didSet {
            problems.attempt("save the morning list") { try Self.settingsKey.save(settings, to: store) }
            rearm()
        }
    }
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let notifications: Notifications
    @ObservationIgnored private let presence: any PresenceSource
    @ObservationIgnored private let zone: TimeZone
    @ObservationIgnored private let needsCount: () -> Int
    @ObservationIgnored private let notify: (String) async -> Bool
    @ObservationIgnored private var isPosting = false
    @ObservationIgnored private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []
    @ObservationIgnored private var morning: Task<Void, Never>?

    /// `needsCount` reads the list as it is now: how many lines ask the person to do something. `notify` posts the
    /// summary through the app's one notification gate and says whether it was posted; the gate holds the daily cap
    /// and the quiet hours.
    init(
        store: Store, notifications: Notifications, presence: any PresenceSource = SystemPresence(),
        zone: TimeZone = .current, needsCount: @escaping () -> Int, notify: @escaping (String) async -> Bool
    ) {
        self.notify = notify
        self.store = store
        self.notifications = notifications
        self.presence = presence
        self.zone = zone
        self.needsCount = needsCount
        problems.attempt("read the morning list settings") {
            settings = try Self.settingsKey.load(from: store) ?? MorningSettings()
        }
    }

    /// Turning it on asks macOS for permission the first time; while macOS blocks notifications it waits.
    func setOn(_ on: Bool) async {
        guard on else {
            settings.isOn = false
            return
        }
        await notifications.whenAllowed { [weak self] in self?.settings.isOn = true }
    }

    /// Starts listening for the moments the list may be due. The first check is at launch: a Mac opened after the
    /// morning hour gets its list then.
    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (workspace, NSWorkspace.didWakeNotification), (workspace, NSWorkspace.screensDidWakeNotification),
            (DistributedNotificationCenter.default(), Self.unlockedEvent),
        ].map { center, name in
            (
                center,
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in await self?.check() }
                }
            )
        }
        rearm()
        Task { await check() }
    }

    func stop() {
        for observer in observers { observer.center.removeObserver(observer.token) }
        observers = []
        morning?.cancel()
        morning = nil
    }

    /// When the schedule wakes next on its own: the next morning hour; nil while the ritual is off.
    func nextWake(after now: Date) -> Date? {
        settings.isOn ? MorningRitual.nextMorning(after: now, hour: settings.hour, zone: zone) : nil
    }

    /// Decides the day's notification if it may be decided now. The day is marked before anything is awaited, so two
    /// wakes at once cannot post twice.
    func check() async {
        let now = store.clock()
        guard settings.isOn, !isPosting,
            MorningRitual.readiness(
                now: now, hour: settings.hour, lastDecided: decidedDay,
                presence: presence.state(idleAfter: Self.idleAfter), zone: zone) == .ready
        else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            try store.fireTimers()
        } catch {
            problems.report("prepare the morning list", error)
            return
        }
        guard let message = MorningRitual.message(needing: needsCount()) else { return markDecided() }
        if await notify(message) { markDecided() }
    }

    private func markDecided() {
        problems.attempt("save the morning list") {
            try Self.decidedKey.save(MorningRitual.day(of: store.clock(), zone: zone), to: store)
        }
    }

    func dismissProblem() { problems.dismiss() }

    private var decidedDay: WorkDay? { (try? Self.decidedKey.load(from: store)) ?? nil }

    private func rearm() {
        morning?.cancel()
        guard observers.isEmpty == false, settings.isOn else {
            morning = nil
            return
        }
        morning = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let next = nextWake(after: store.clock()) else { return }
                try? await Task.sleep(for: .seconds(next.timeIntervalSince(store.clock()) + 1))
                guard !Task.isCancelled else { return }
                await check()
            }
        }
    }
}

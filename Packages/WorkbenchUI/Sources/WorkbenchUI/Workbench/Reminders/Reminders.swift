import Foundation
import Observation
import WorkbenchCore

/// The founder's reminders: a silent digest of what waits in Review at set times, and Mochi's weekly look for
/// repeated work. Both are off until the founder turns them on. Each runs at most once per slot, and a Mac that sleeps
/// through a slot catches up when it wakes, until the next slot.
@Observable
final class Reminders {
    struct Settings: Codable, Equatable {
        var digest = false
        var weeklyMochi = false
        /// Hours of the digest, in the founder's day. Two a day: batching helped where hourly did not (research 23).
        var digestHours = [9, 15]
    }

    private static let settingsKey = StateKey<Settings>.json("reminders")
    private static let digestKey = StateKey<String>.text("reminders.digest.sent")
    private static let mochiKey = StateKey<Date>.moment("reminders.mochi.ran")
    static let mochiHour = 18
    static let week: TimeInterval = 7 * 86_400

    var settings = Settings() {
        didSet { problems.attempt("save the reminders") { try Self.settingsKey.save(settings, to: store) } }
    }
    /// Mochi's brief of the day before, each morning from `briefHour`. Its own key, so older saved settings still read.
    var morningBrief = false {
        didSet { problems.attempt("save the reminders") { try Self.briefSettingKey.save(morningBrief, to: store) } }
    }
    static let briefHour = 9
    private static let briefSettingKey = StateKey<Bool>.onOff("reminders.brief")
    private static let briefDayKey = StateKey<WorkDay>.day("reminders.brief.day")
    let problems = ProblemSlot()
    var problem: String? { problems.text }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let review: ReviewModel
    @ObservationIgnored private let mochi: MochiModel
    let notifications: Notifications
    @ObservationIgnored private let ticker = Ticker()

    convenience init(store: Store, review: ReviewModel, mochi: MochiModel, notifier: Notifier = SystemNotifier()) {
        self.init(store: store, review: review, mochi: mochi, notifications: Notifications(notifier: notifier))
    }

    init(store: Store, review: ReviewModel, mochi: MochiModel, notifications: Notifications) {
        self.store = store
        self.review = review
        self.mochi = mochi
        self.notifications = notifications
        problems.attempt("read the reminders") { settings = try Self.settingsKey.load(from: store) ?? Settings() }
        morningBrief = state(Self.briefSettingKey) ?? false
    }

    /// Turning the digest on asks macOS for permission the first time.
    func setDigest(on: Bool) async {
        guard on else {
            settings.digest = false
            return
        }
        await notifications.whenAllowed { [weak self] in self?.settings.digest = true }
    }

    /// Checks once a minute while the app runs, until the reminders are stopped or released.
    func start() {
        ticker.start { [weak self] in await self?.tick() }
    }

    func stop() { ticker.stop() }

    /// The latest digest slot at or before `now`, as a key: the day and the hour.
    static func slot(at now: Date, hours: [Int], calendar: Calendar = .current) -> String? {
        let hour = calendar.component(.hour, from: now)
        guard let due = hours.filter({ $0 <= hour }).max() else { return nil }
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d %02d", day.year!, day.month!, day.day!, due)
    }

    /// The brief notifies, so it needs notifications; while macOS blocks them it waits and turns on once allowed.
    func setMorningBrief(on: Bool) async {
        guard on else {
            morningBrief = false
            return
        }
        await notifications.whenAllowed { [weak self] in self?.morningBrief = true }
    }

    func tick() async {
        let now = store.clock()
        let today = WorkDay(containing: now)
        if morningBrief, Calendar.current.component(.hour, from: now) >= Self.briefHour,
            state(Self.briefDayKey) != today
        {
            problems.attempt("save the reminders") { try Self.briefDayKey.save(today, to: store) }
            // A quiet day is kept on Mochi's page without an alert: alerts that rarely matter teach people to ignore
            // them (research: clinical alert override rates).
            if let brief = await mochi.writeBrief(for: today.adding(days: -1)), !brief.isQuiet {
                await post("Mochi's brief", brief.headline, page: .day)
            }
        }
        if settings.digest, let slot = Self.slot(at: now, hours: settings.digestHours), slot != state(Self.digestKey) {
            problems.attempt("save the reminders") { try Self.digestKey.save(slot, to: store) }
            review.refresh()
            if !review.items.isEmpty {
                await post(
                    "Review", "\(review.items.count) to review, \(review.questions) picked at random.", page: .review)
            }
        }
        if settings.weeklyMochi, isMochiDue(at: now) {
            problems.attempt("save the reminders") { try Self.mochiKey.save(now, to: store) }
            let before = Set(mochi.waiting.compactMap(\.id))
            await mochi.discover()
            let new = mochi.waiting.filter { $0.id.map { !before.contains($0) } ?? false }
            if !new.isEmpty {
                await post(
                    "Mochi", "Mochi suggests \(new.count) machine\(new.count == 1 ? "" : "s") for work you repeat.",
                    page: .day)
            }
        }
    }

    func isMochiDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.hour, from: now) >= Self.mochiHour, mochi.canDiscover else { return false }
        guard let last = state(Self.mochiKey) else { return true }
        return now.timeIntervalSince(last) >= Self.week - 12 * 3600
    }

    private func post(_ title: String, _ body: String, page: SidebarSelection) async {
        do {
            try await notifications.post(title: title, body: body, page: page)
        } catch {
            problems.report("show a reminder", error)
        }
    }

    private func state<Value>(_ key: StateKey<Value>) -> Value? { (try? key.load(from: store)) ?? nil }
}

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

    private static let settingsKey = "reminders"
    private static let digestKey = "reminders.digest.sent"
    private static let mochiKey = "reminders.mochi.ran"
    /// Mochi runs once a week, in the evening.
    static let mochiHour = 18
    static let week: TimeInterval = 7 * 86_400

    var settings = Settings() {
        didSet { attempt { try store.saveState(Self.json(settings), forKey: Self.settingsKey) } }
    }
    /// Mochi's brief of the day before, each morning from `briefHour`. Its own key, so older saved settings still read.
    var morningBrief = false {
        didSet { attempt { try store.saveState(morningBrief ? "on" : "off", forKey: Self.briefSettingKey) } }
    }
    static let briefHour = 9
    private static let briefSettingKey = "reminders.brief"
    private static let briefDayKey = "reminders.brief.day"
    private(set) var problem: String?

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let review: ReviewModel
    @ObservationIgnored private let mochi: MochiModel
    let notifications: Notifications
    @ObservationIgnored private var ticker: Task<Void, Never>?

    convenience init(store: Store, review: ReviewModel, mochi: MochiModel, notifier: Notifier = SystemNotifier()) {
        self.init(store: store, review: review, mochi: mochi, notifications: Notifications(notifier: notifier))
    }

    init(store: Store, review: ReviewModel, mochi: MochiModel, notifications: Notifications) {
        self.store = store
        self.review = review
        self.mochi = mochi
        self.notifications = notifications
        attempt {
            settings =
                try store.queries.state(forKey: Self.settingsKey).map {
                    try JSONDecoder().decode(Settings.self, from: Data($0.utf8))
                } ?? Settings()
        }
        morningBrief = state(Self.briefSettingKey) == "on"
    }

    /// Turning the digest on asks macOS for permission the first time.
    func setDigest(on: Bool) async {
        guard on else {
            settings.digest = false
            return
        }
        await notifications.whenAllowed { [weak self] in self?.settings.digest = true }
    }

    func start() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

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
            state(Self.briefDayKey) != today.description
        {
            attempt { try store.saveState(today.description, forKey: Self.briefDayKey) }
            if let brief = await mochi.writeBrief(for: today.adding(days: -1)) {
                let first = brief.lines.first { $0.kind == .next } ?? brief.lines.first
                await post("Mochi's brief", first.map { "\($0.text) (\(brief.lines.count) lines in Workbench)" } ?? "")
            }
        }
        if settings.digest, let slot = Self.slot(at: now, hours: settings.digestHours), slot != state(Self.digestKey) {
            attempt { try store.saveState(slot, forKey: Self.digestKey) }
            review.refresh()
            if !review.items.isEmpty {
                await post(
                    "Review",
                    "\(review.items.count) to review, \(review.questions) picked at random. Open Workbench › Review.")
            }
        }
        if settings.weeklyMochi, isMochiDue(at: now) {
            attempt { try store.saveState(now.ISO8601Format(), forKey: Self.mochiKey) }
            let before = Set(mochi.waiting.compactMap(\.id))
            await mochi.discover()
            let new = mochi.waiting.filter { $0.id.map { !before.contains($0) } ?? false }
            if !new.isEmpty {
                await post(
                    "Mochi", "Mochi suggests \(new.count) machine\(new.count == 1 ? "" : "s") for work you repeat.")
            }
        }
    }

    func isMochiDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard calendar.component(.hour, from: now) >= Self.mochiHour, mochi.canDiscover else { return false }
        guard let last = state(Self.mochiKey).flatMap({ try? Date($0, strategy: .iso8601) }) else { return true }
        return now.timeIntervalSince(last) >= Self.week - 12 * 3600
    }

    func dismissProblem() { problem = nil }

    private func post(_ title: String, _ body: String) async {
        do {
            try await notifications.post(title: title, body: body)
        } catch {
            problem = "Could not show a reminder: \(error.localizedDescription)"
        }
    }

    private func state(_ key: String) -> String? { (try? store.queries.state(forKey: key)) ?? nil }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            problem = "Could not save the reminders: \(error.localizedDescription)"
        }
    }

    private static func json(_ value: some Encodable) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}

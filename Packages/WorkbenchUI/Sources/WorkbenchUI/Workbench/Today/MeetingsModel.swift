import Foundation
import LocalSources
import Observation
import WorkbenchCore

/// Today's meetings from the Mac's calendar. It reads only while the calendar consent is on, keeps nothing on disk,
/// and drops what it read as soon as the consent goes off. A model with no calendar never reads and never offers.
@Observable
final class MeetingsModel {
    static let offerDeclinedKey = "calendarOfferDeclined"
    static let skipsAllDayKey = "calendar.skipsAllDay"

    private(set) var day = CalendarDay.empty
    private(set) var isOn = false
    private(set) var offerDeclined: Bool
    /// One line saying why the calendar cannot be read, while macOS refuses it.
    private(set) var refusal: String?
    /// Whether holidays, birthdays and other all-day events stay off Mochi's page and the pop-up: on until the
    /// person turns it off. This is the one all-day filter; the reader returns every event with its `isAllDay`.
    var skipsAllDay: Bool {
        didSet { defaults.set(skipsAllDay, forKey: Self.skipsAllDayKey) }
    }

    @ObservationIgnored private let store: Store
    @ObservationIgnored private let reader: MeetingReader?
    @ObservationIgnored private let defaults: UserDefaults

    init(store: Store, calendar: (any CalendarEvents)?, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        offerDeclined = defaults.bool(forKey: Self.offerDeclinedKey)
        skipsAllDay = defaults.object(forKey: Self.skipsAllDayKey) as? Bool ?? true
        reader = calendar.map { MeetingReader(calendar: $0, policy: store) }
    }

    var meetings: [Meeting] { skipsAllDay ? day.meetings.filter { !$0.isAllDay } : day.meetings }
    var calendars: [CalendarInfo] { day.calendars }

    /// Whether Today may ask once to show the meetings: the calendar is off and the person has not said no.
    var offersMeetings: Bool { reader != nil && !isOn && !offerDeclined }

    func declineOffer() {
        offerDeclined = true
        defaults.set(true, forKey: Self.offerDeclinedKey)
    }

    func refresh() async {
        guard let reader else { return }
        isOn = (try? store.currentPolicy().isEnabled(.calendar)) ?? false
        do {
            day = try await reader.today(at: store.clock())
            refusal = nil
        } catch CalendarError.accessRefused(let access) {
            day = .empty
            refusal = Self.sentence(access)
        } catch {
            day = .empty
            refusal = nil
        }
    }

    private static func sentence(_ access: SystemAccess) -> String {
        switch access {
        case .failed(let reason): "macOS refused calendar access: \(reason)"
        case .allowed, .blocked: "macOS has not given Workbench access to your calendar."
        }
    }
}

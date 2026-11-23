import Foundation
import LocalSources
import Observation
import WorkbenchCore

@Observable
final class MeetingsModel {
    static let offerDeclinedKey = "calendarOfferDeclined"
    static let skipsAllDayKey = "calendar.skipsAllDay"

    private(set) var day = CalendarDay.empty
    private(set) var isOn = false
    private(set) var offerDeclined: Bool
    private(set) var refusal: String?
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

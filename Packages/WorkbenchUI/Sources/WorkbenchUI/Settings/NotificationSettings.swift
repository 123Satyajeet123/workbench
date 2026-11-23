import Foundation
import SwiftUI

/// A daily stretch with no notifications. It can cross midnight: 22:00 to 08:00 holds 23:30 and 07:59, not 08:00.
struct QuietHours: Equatable {
    var isOn: Bool
    /// Minutes after midnight.
    var start: Int
    var end: Int

    func contains(_ moment: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: moment) * 60 + calendar.component(.minute, from: moment)
        guard isOn, start != end else { return false }
        return start < end ? (start..<end).contains(minute) : minute >= start || minute < end
    }
}

/// How many notifications a day, and when none. Kept in the app's defaults: three a day, quiet from 22:00 to 08:00.
struct NotificationPolicy: Equatable {
    static let capChoices = [1, 2, 3, 5, 10]

    var dailyCap = 3
    var quiet = QuietHours(isOn: true, start: 22 * 60, end: 8 * 60)

    private static let capKey = "notifications.dailyCap"
    private static let quietOnKey = "notifications.quietOn"
    private static let quietStartKey = "notifications.quietStart"
    private static let quietEndKey = "notifications.quietEnd"

    static func saved(in defaults: UserDefaults) -> Self {
        let standard = Self()
        return Self(
            dailyCap: defaults.object(forKey: capKey) as? Int ?? standard.dailyCap,
            quiet: QuietHours(
                isOn: defaults.object(forKey: quietOnKey) as? Bool ?? standard.quiet.isOn,
                start: defaults.object(forKey: quietStartKey) as? Int ?? standard.quiet.start,
                end: defaults.object(forKey: quietEndKey) as? Int ?? standard.quiet.end))
    }

    func save(in defaults: UserDefaults) {
        defaults.set(dailyCap, forKey: Self.capKey)
        defaults.set(quiet.isOn, forKey: Self.quietOnKey)
        defaults.set(quiet.start, forKey: Self.quietStartKey)
        defaults.set(quiet.end, forKey: Self.quietEndKey)
    }
}

/// Settings › Notifications: how many a day, and the quiet hours.
struct NotificationSettingsView: View {
    private let defaults: UserDefaults
    @State private var policy: NotificationPolicy

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _policy = State(initialValue: .saved(in: defaults))
    }

    var body: some View {
        Form {
            Section {
                Picker("Most a day", selection: $policy.dailyCap) {
                    ForEach(NotificationPolicy.capChoices, id: \.self) { Text("\($0)").tag($0) }
                }
            } header: {
                Text("How many")
            } footer: {
                FormNote(
                    "Workbench shows no notification while its window is in front."
                )
            }
            Section {
                Toggle("Quiet hours", isOn: $policy.quiet.isOn)
                if policy.quiet.isOn {
                    DatePicker("From", selection: minutes($policy.quiet.start), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minutes($policy.quiet.end), displayedComponents: .hourAndMinute)
                }
            } header: {
                Text("When")
            } footer: {
                FormNote("In quiet hours Workbench shows no notification, even when a fact needs you.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: policy) { _, policy in policy.save(in: defaults) }
    }

    private func minutes(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: .now)
                    ?? .now
            },
            set: {
                minutes.wrappedValue =
                    Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0)
            })
    }
}

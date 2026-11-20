import SwiftUI

/// Which calendars Today reads: all of them until the person unticks one.
struct CalendarChooser: View {
    let calendars: [CalendarChoice]
    let toggle: (CalendarChoice) -> Void

    var body: some View {
        ForEach(calendars) { calendar in
            Toggle(calendar.title, isOn: Binding(get: { calendar.isRead }, set: { _ in toggle(calendar) }))
                .toggleStyle(.checkbox).padding(.leading, Space.l)
        }
    }
}

/// A calendar and whether Today reads it.
struct CalendarChoice: Identifiable, Equatable {
    var id: String
    var title: String
    var isRead: Bool
}

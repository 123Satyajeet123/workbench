import SwiftUI

/// Settings › General › Reminders: the digest and Mochi's weekly run, both off until turned on.
struct RemindersSection: View {
    @Environment(Reminders.self) private var reminders
    @Environment(Notifications.self) private var notifications

    var body: some View {
        Section {
            Toggle(
                "Digest of what waits in Review",
                isOn: Binding(
                    get: { reminders.settings.digest }, set: { on in Task { await reminders.setDigest(on: on) } }))
            if notifications.blocked {
                HStack {
                    FormNote("macOS blocks Workbench notifications.")
                    Button("Allow in System Settings", action: SystemNotifier.openSettings)
                }
            }
            Toggle(
                "Morning brief from Mochi at \(String(format: "%02d:00", Reminders.briefHour))",
                isOn: Binding(
                    get: { reminders.morningBrief },
                    set: { on in Task { await reminders.setMorningBrief(on: on) } }))
            @Bindable var reminders = reminders
            Toggle("Mochi looks for repeated work every week", isOn: $reminders.settings.weeklyMochi)
        } header: {
            Text("Reminders")
        } footer: {
            FormNote(
                "The digest is silent, at \(reminders.settings.digestHours.map { String(format: "%02d:00", $0) }.formatted(.list(type: .and))), and only when something waits. Mochi's weekly run reads your marked timeline with your chosen model on an evening after a week, then tells you if it has suggestions."
            )
            if let problem = reminders.problem { FormNote(problem) }
        }
    }
}

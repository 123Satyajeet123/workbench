import SwiftUI
import WorkbenchCore

/// Reading through the day: new lines once an hour inside the reading hours, and an alert for new items the spec
/// marks bad.
struct WatchRow: View {
    let model: HelperModel
    @Environment(ModelSettings.self) private var models

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Toggle(
                label, isOn: Binding(get: { model.watch.isOn }, set: { on in Task { await model.setWatch(on: on) } }))
            Text(note)
                .textStyle(.callout).foregroundStyle(.supporting)
        }
    }

    private var label: String {
        "Read new \(model.spec.source.lineNoun) every hour, \(model.watch.fromHour):00–\(model.watch.untilHour):00"
    }

    private var note: String {
        let alert = model.spec.tones.values.contains(.bad) ? " You get an alert for new \(alarming)." : ""
        return "Each reading with something new is one call to \(models.choice.title); nothing new, no call.\(alert)"
    }

    private var alarming: String {
        let values = model.spec.tones.filter { $0.value == .bad }.keys.sorted()
        return values.isEmpty ? model.spec.itemsNoun : values.map { "\($0)s" }.formatted(.list(type: .or))
    }
}

/// The once-a-day nudge: on or off, and its time.
struct NudgeRow: View {
    let model: HelperModel
    @Environment(ModelSettings.self) private var models

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.m) {
                Toggle(
                    "Night nudge",
                    isOn: Binding(get: { model.nudge.isOn }, set: { on in Task { await model.setNudge(on: on) } }))
                DatePicker("at", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!model.nudge.isOn)
            }
            Text(
                "At this time \(model.name) reads today with \(models.choice.title) and tells you who has no \(model.spec.itemsNoun). Silent; the Mac must be on."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            if model.notifications.blocked {
                HStack(spacing: Space.s) {
                    Label("macOS blocks Workbench notifications.", systemImage: "bell.slash")
                        .foregroundStyle(Tone.attention.color)
                    Button("Allow in System Settings", action: SystemNotifier.openSettings)
                }
                .textStyle(.callout)
            }
        }
    }

    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: model.nudge.hour, minute: model.nudge.minute, second: 0, of: .now)
                    ?? .now
            },
            set: {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                model.nudge.hour = parts.hour ?? model.nudge.hour
                model.nudge.minute = parts.minute ?? model.nudge.minute
            })
    }
}

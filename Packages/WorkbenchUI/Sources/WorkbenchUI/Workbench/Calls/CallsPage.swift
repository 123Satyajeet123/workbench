import SwiftUI
import WorkbenchCore

/// The calls helper: the calls recorded on this Mac in the last week, newest first, each saved or failed with its reason.
struct CallsPage: View {
    private static let days = 7

    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        Page(
            title: SidebarSelection.calls.title,
            subtitle: "Calls recorded on this Mac. Start and stop a recording from the menu bar.",
            look: SidebarSelection.calls.look
        ) {
            if let call = capture.call {
                Label(
                    "Recording \(call.app) since \(call.startedAt.formatted(date: .omitted, time: .shortened))",
                    systemImage: "record.circle"
                )
                .foregroundStyle(Tone.bad.color)
            }
            let recordings = capture.recordings(
                since: Calendar.current.date(byAdding: .day, value: -Self.days, to: .now)!
            )
            .filter { $0.state != .recording }
            if recordings.isEmpty {
                Text("No call recorded in the last \(Self.days) days.").foregroundStyle(.supporting)
            }
            ForEach(
                Dictionary(grouping: recordings) { Calendar.current.startOfDay(for: $0.startedAt) }.sorted {
                    $0.key > $1.key
                }, id: \.key
            ) { day, calls in
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month())).font(.headline)
                    ForEach(calls.sorted { $0.startedAt > $1.startedAt }) { RecordingRow(recording: $0) }
                }
                Divider()
            }
        }
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(recording.app)
            Text(span).foregroundStyle(.supporting).monospacedDigit()
            Spacer()
            if recording.state == .saved {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([recording.folder]) }
                    .buttonStyle(.borderless)
                Text("Saved").foregroundStyle(Tone.good.color)
            } else {
                Text(recording.error ?? "Failed").foregroundStyle(Tone.bad.color).textSelection(.enabled)
            }
        }
        .font(.callout)
    }

    private var span: String {
        let start = recording.startedAt.formatted(date: .omitted, time: .shortened)
        guard let end = recording.endedAt else { return start }
        let minutes = Int(end.timeIntervalSince(recording.startedAt) / 60)
        return "\(start) · \(minutes) min"
    }
}

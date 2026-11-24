import SwiftUI
import WorkbenchCore

/// What a machine says of itself: one sentence from `MachineStatus`, and on a machine's own page a fold with the
/// journal of its latest reading, one line for each event. The status is read again every minute, and every two
/// seconds while a reading runs, so a time that passes (a pause that ends, a reading that falls due) shows.
struct MachineStatusView: View {
    enum Shows {
        case sentence
        /// The sentence, and a fold with the lines of the latest reading's journal.
        case journal(isOpen: Bool)
    }

    let isReading: Bool
    let shows: Shows
    let read: (Date) -> Result<MachineStatus, any Error>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: isReading ? 2 : 60)) { timeline in
            switch read(timeline.date) {
            case nil: EmptyView()
            case .failure(let error): Text("Could not read the status: \(error.localizedDescription)").text(.meta)
            case .success(let status): content(status)
            }
        }
    }

    private func content(_ status: MachineStatus) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(status.sentence).text(.meta)
            if case .journal(let isOpen) = shows, let latest = status.latest {
                Fold(isOpen: isOpen) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(latest.lines.enumerated()), id: \.offset) { Text($0.element).textStyle(.body) }
                    }
                    .padding(.top, Space.xs)
                } label: {
                    Text("Last reading").text(.meta)
                }
            }
        }
    }
}

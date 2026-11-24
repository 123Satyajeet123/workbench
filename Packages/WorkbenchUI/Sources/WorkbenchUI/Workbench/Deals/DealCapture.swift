import SwiftUI
import WorkbenchCore

extension DealStory.Ribbon {
    var words: [String] {
        [
            sources.isEmpty ? "Made by hand" : "From \(sources.formatted(.list(type: .and)))",
            rating.map { "Rated \($0)" } ?? "Not rated",
            mark.map { $0 == .confirmed ? "You marked it right" : "You marked it wrong" } ?? "Not marked",
            "\(moves) \(moves == 1 ? "move" : "moves")",
            "Actions: \(actionsOpened) opened, \(actionsClosed) closed",
        ]
    }
}

struct CaptureRibbon: View {
    let ribbon: DealStory.Ribbon

    var body: some View {
        Label(ribbon.words.joined(separator: " · "), systemImage: "waveform.path.ecg")
            .textStyle(.caption).foregroundStyle(.supporting)
            .accessibilityLabel("Captured: \(ribbon.words.joined(separator: ", "))")
    }
}

struct DealTimeline: View {
    let entries: [DealStory.Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(entries) { entry in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    actor(entry).zoomedWidth(18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text).textStyle(.callout).textSelection(.enabled)
                        Text(entry.at.formatted(date: .abbreviated, time: .shortened))
                            .textStyle(.caption).foregroundStyle(.supporting)
                    }
                }
            }
        }
    }

    @ViewBuilder private func actor(_ entry: DealStory.Entry) -> some View {
        if entry.isMachine {
            Image(systemName: "gearshape").accessibilityLabel("Machine \(entry.actor)")
        } else {
            Text(entry.actor.prefix(1).uppercased()).fontWeight(.semibold).accessibilityLabel(entry.actor)
        }
    }
}

struct AutomationStripView: View {
    let rows: [AutomationRow]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(row.name) · \(row.role)").fontWeight(.medium)
                    Text("\(row.lastRun). \(row.nextRun).").textStyle(.callout).foregroundStyle(.supporting)
                    Text(row.precision).textStyle(.callout)
                    if let rule = row.rule { Text(rule).textStyle(.callout).foregroundStyle(.supporting) }
                }
                .calloutBox(padding: Space.s, fillsWidth: true)
            }
        }
    }
}

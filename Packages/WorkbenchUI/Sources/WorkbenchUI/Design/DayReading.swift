import SwiftUI
import WorkbenchCore

enum ReadPhase: Equatable {
    case idle
    case reading
    case read(kept: Int, dropped: Int)
    case upToDate
}

struct ReadPhaseLabel: View {
    let phase: ReadPhase
    let items: String
    let droppedBecause: String

    var body: some View {
        switch phase {
        case .idle: EmptyView()
        case .reading: ProgressView("Reading the day…").controlSize(.small)
        case .upToDate:
            Text("Nothing new since the last reading.").textStyle(.callout).foregroundStyle(.supporting)
        case .read(let kept, let dropped):
            Text(
                dropped == 0
                    ? "\(items.capitalized): \(kept)."
                    : "\(items.capitalized): \(kept). Dropped: \(dropped), \(droppedBecause)."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
        }
    }
}

struct DayStepper: View {
    let day: WorkDay
    let today: WorkDay
    let show: (WorkDay) -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Button("Previous day", systemImage: "chevron.left") { show(day.adding(days: -1)) }
            Text(day.start.formatted(.dateTime.weekday(.wide).day().month())).monospacedDigit()
                .frame(minWidth: 150)
            Button("Next day", systemImage: "chevron.right") { show(day.adding(days: 1)) }
                .disabled(day >= today)
        }
        .labelStyle(.iconOnly)
    }
}

struct MarkButtons: View {
    let state: Mark
    let mark: (Mark) -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Button("Right", systemImage: state == .confirmed ? "checkmark.circle.fill" : "checkmark.circle") {
                mark(.confirmed)
            }
            .foregroundStyle(state == .confirmed ? Tone.good.color : .supporting)
            Button("Wrong", systemImage: state == .rejected ? "xmark.circle.fill" : "xmark.circle") {
                mark(.rejected)
            }
            .foregroundStyle(state == .rejected ? Tone.bad.color : .supporting)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.ghost)
    }
}

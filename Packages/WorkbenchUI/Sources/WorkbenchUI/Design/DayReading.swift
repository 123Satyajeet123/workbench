import SwiftUI
import WorkbenchCore

/// Where the read of one day stands. Every helper that reads a day with a model shows this.
enum ReadPhase: Equatable {
    case idle
    case reading
    case read(kept: Int, dropped: Int)
}

struct ReadPhaseLabel: View {
    let phase: ReadPhase
    /// What a kept item is called: "entries", "blocks".
    let items: String
    /// Why an item was dropped, in a few words.
    let droppedBecause: String

    var body: some View {
        switch phase {
        case .idle: EmptyView()
        case .reading: ProgressView("Reading the day…").controlSize(.small)
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

/// Back and forward one work day; never past today.
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

/// The founder's right/wrong on one proposed item. Pressing the current mark again takes it back.
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
        .buttonStyle(.borderless)
    }
}

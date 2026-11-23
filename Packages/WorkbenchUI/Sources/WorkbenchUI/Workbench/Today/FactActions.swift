import SwiftUI
import WorkbenchCore

struct FactActions: View {
    let items: [Item]
    let summary: String
    let model: TodayModel

    var body: some View {
        HStack(spacing: Space.xs) {
            if model.isDone(items) {
                Button("Reopen", systemImage: "checkmark.circle.fill") { model.reopen(items) }
                    .foregroundStyle(Tone.good.color)
                    .help("Done. Click to reopen it")
            } else if items.contains(where: model.isClosable) {
                Button("Done", systemImage: "checkmark.circle") { act(.done, "Done") }
                    .help("Done: close it")
            }
            Menu("More", systemImage: "ellipsis.circle") {
                Menu("Snooze", systemImage: "clock") {
                    ForEach(Self.snoozes, id: \.title) { snooze in
                        Button(snooze.title) { act(.snooze(until: model.today.adding(days: snooze.days)), "Snoozed") }
                    }
                }
                Button("Right", systemImage: "hand.thumbsup") { act(.right, "Marked right") }
                Button("Not relevant", systemImage: "eye.slash") { act(.notRelevant, "Hidden as not relevant") }
                Button("Wrong", systemImage: "xmark.circle") { act(.wrong, "Hidden as wrong") }
            }
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
        }
        .labelStyle(.iconOnly).buttonStyle(.ghost).fixedSize()
    }

    private static let snoozes: [(title: String, days: Int)] = [
        ("Until tomorrow", 1), ("For 3 days", 3), ("For a week", 7),
    ]

    private func act(_ choice: FactChoice, _ verb: String) {
        model.perform(choice, on: items, text: "\(verb): \(summary)")
    }
}

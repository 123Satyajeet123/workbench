import SwiftUI
import WorkbenchCore

/// What the founder can do with a fact, or with the facts a summary line cites: done, and a menu for the rest. Each
/// one is a mark or an event that Undo takes back.
struct FactActions: View {
    let items: [Item]
    let summary: String
    let model: TodayModel

    var body: some View {
        HStack(spacing: Space.xs) {
            Button("Done", systemImage: "checkmark.circle") { act(.done, "Done") }
                .help("Done: close it")
            Menu("More", systemImage: "ellipsis.circle") {
                Menu("Snooze", systemImage: "clock") {
                    ForEach(Self.snoozes, id: \.title) { snooze in
                        Button(snooze.title) { act(.snooze(until: model.today.adding(days: snooze.days)), "Snoozed") }
                    }
                }
                if !model.handOffPeople.isEmpty {
                    Menu("Hand off to", systemImage: "arrowshape.turn.up.right") {
                        ForEach(model.handOffPeople, id: \.self) { person in
                            Button(person) { act(.handOff(to: person), "Handed to \(person)") }
                        }
                    }
                }
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

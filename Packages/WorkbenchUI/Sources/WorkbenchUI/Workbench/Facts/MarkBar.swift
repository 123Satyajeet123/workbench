import SwiftUI

/// The actions of one fact: the one question as buttons, each with its key, and the other actions in a "⋯" menu. A
/// snooze opens its three lengths.
struct MarkBar: View {
    let actions: [FactAction]
    let act: (FactAction) -> Void

    var body: some View {
        let split = FactAction.split(actions)
        HStack(spacing: Space.xs) {
            ForEach(split.primary, id: \.self) { action in
                Button {
                    act(action)
                } label: {
                    label(of: action)
                }
                .accessibilityLabel(action.title)
                .accessibilityHint("Key \(action.key)")
            }
            if !split.more.isEmpty { menu(split.more) }
        }
        .buttonStyle(.ghost)
        .fixedSize()
    }

    private func menu(_ actions: [FactAction]) -> some View {
        Menu {
            ForEach(actions, id: \.self) { action in
                if case .snooze = action {
                    Menu("\(action.title) (\(action.key))") {
                        ForEach(FactAction.snoozes, id: \.self) { length in
                            Button(length.choiceTitle) { act(length) }
                        }
                    }
                } else {
                    Button("\(action.title) (\(action.key))") { act(action) }
                }
            }
        } label: {
            Image(systemName: "ellipsis").zoomedWidth(20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(.supporting)
        .tint(.supporting)
        .accessibilityLabel("More actions")
    }

    private func label(of action: FactAction) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: action.symbol)
            Text(action.title)
            KeyHint(action.key)
        }
        .help("\(action.title) (\(action.key))")
    }
}

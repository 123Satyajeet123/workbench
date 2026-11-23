import SwiftUI

/// The actions of one fact as small icon buttons, each with its key. A snooze opens a short list of its three lengths.
struct MarkBar: View {
    let actions: [FactAction]
    /// True while the list of snooze lengths is open, so the host keeps the bar on screen.
    @Binding var isChoosing: Bool
    let act: (FactAction) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(actions, id: \.self) { action in
                Button {
                    press(action)
                } label: {
                    label(of: action)
                }
                .accessibilityLabel(action.title)
                .accessibilityHint("Key \(action.key)")
                .popover(isPresented: popover(for: action), arrowEdge: .bottom) { lengths }
            }
        }
        .buttonStyle(.ghost)
        .fixedSize()
    }

    private func press(_ action: FactAction) {
        if case .snooze = action { isChoosing.toggle() } else { act(action) }
    }

    private func popover(for action: FactAction) -> Binding<Bool> {
        guard case .snooze = action else { return .constant(false) }
        return $isChoosing
    }

    private var lengths: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(FactAction.snoozes, id: \.self) { length in
                Button(length.choiceTitle) {
                    isChoosing = false
                    act(length)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.ghost)
        .padding(Space.xs)
    }

    private func label(of action: FactAction) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: action.symbol).frame(width: 20)
            KeyHint(action.key)
        }
        .help("\(action.title) (\(action.key))")
    }
}

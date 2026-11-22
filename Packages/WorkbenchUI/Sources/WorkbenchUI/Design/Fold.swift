import SwiftUI

struct Fold<Label: View, Content: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let label: Label
    @State private var isOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.iconTint)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 12)
                    label
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            if isOpen {
                content
                    .padding(.leading, 12 + Space.s)
                    .transition(.opacity)
            }
        }
    }

    private func toggle() {
        withAnimation(Motion.settle(reduceMotion: reduceMotion)) { isOpen.toggle() }
    }
}

extension Fold where Label == Text {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, label: { Text(title) })
    }
}

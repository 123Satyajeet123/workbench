import SwiftUI

struct FoldStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        Fold(configuration: configuration)
    }
}

extension DisclosureGroupStyle where Self == FoldStyle {
    static var fold: FoldStyle { FoldStyle() }
}

private struct Fold: View {
    let configuration: DisclosureGroupStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Button(action: toggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.iconTint)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(configuration.isExpanded ? "Collapse" : "Expand")
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .onTapGesture(perform: toggle)
            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 12 + Space.s)
                    .transition(.opacity)
            }
        }
    }

    private func toggle() {
        withAnimation(Motion.settle(reduceMotion: reduceMotion)) { configuration.isExpanded.toggle() }
    }
}

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
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.iconTint)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                        .frame(width: 12)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
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

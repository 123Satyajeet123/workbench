import SwiftUI

/// While a call records: the notch grows a red dot on the left and the running time on the right. Otherwise nothing.
struct IslandView: View {
    let recordingSince: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let recordingSince {
                shape.fill(.black)
                HStack(spacing: 0) {
                    Image(systemName: "record.circle.fill").foregroundStyle(Tone.bad.color)
                        .frame(width: IslandMetrics.earWidth)
                    Spacer(minLength: IslandMetrics.notchWidth)
                    Text(recordingSince, style: .timer).textStyle(.callout, weight: .medium).monospacedDigit()
                        .frame(width: IslandMetrics.earWidth)
                }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Recording a call")
            }
        }
        .frame(width: width, height: IslandMetrics.notchHeight)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        .animation(
            reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.15), value: recordingSince)
    }

    private var width: CGFloat {
        IslandMetrics.notchWidth + (recordingSince == nil ? 0 : 2 * IslandMetrics.earWidth)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous)
    }
}

#Preview("Recording") {
    IslandView(recordingSince: .now.addingTimeInterval(-95)).frame(width: 440, height: 60)
}

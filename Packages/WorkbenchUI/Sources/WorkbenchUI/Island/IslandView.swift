import SwiftUI

/// The notch grows ears only when there is something to show: a red dot and the running time while a call records, the
/// name of a machine while it reads, or how many items wait for the founder. Otherwise nothing. It changes only when a
/// recording or a reading starts or ends, and only the recording dot moves.
struct IslandView: View {
    let state: IslandState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if state != .idle {
                shape.fill(.black)
                HStack(spacing: 0) {
                    ear { leading }
                    Spacer(minLength: IslandMetrics.notchWidth)
                    ear { trailing }
                }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
            }
        }
        .frame(width: width, height: IslandMetrics.notchHeight)
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.15), value: state)
    }

    @ViewBuilder private var leading: some View {
        switch state {
        case .idle: EmptyView()
        case .recording:
            Image(systemName: "record.circle.fill").foregroundStyle(Tone.bad.color)
                .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.45]) { dot, opacity in
                    dot.opacity(opacity)
                } animation: {
                    _ in
                    .easeInOut(duration: 0.9)
                }
        case .reading: Image(systemName: "text.magnifyingglass").foregroundStyle(.white)
        case .waiting: Image(systemName: "tray.full.fill").foregroundStyle(Tone.attention.color)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .idle: EmptyView()
        case .recording(let since): Text(since, style: .timer).monospacedDigit()
        case .reading(let machine): Text(machine).lineLimit(1).minimumScaleFactor(0.7)
        case .waiting(let count): Text("\(count)").monospacedDigit()
        }
    }

    private func ear(@ViewBuilder _ content: () -> some View) -> some View {
        content().textStyle(.callout, weight: .medium).frame(width: IslandMetrics.earWidth)
    }

    private var label: String {
        switch state {
        case .idle: ""
        case .recording: "Recording a call"
        case .reading(let machine): "\(machine) is reading"
        case .waiting(let count): "\(count) items wait for your review. Click to review."
        }
    }

    private var width: CGFloat {
        IslandMetrics.notchWidth + (state == .idle ? 0 : 2 * IslandMetrics.earWidth)
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous)
    }
}

#Preview("Recording") {
    IslandView(state: .recording(since: .now.addingTimeInterval(-95))).frame(width: 440, height: 60)
}

#Preview("Reading") {
    IslandView(state: .reading(machine: "Atlas")).frame(width: 440, height: 60)
}

#Preview("Waiting") {
    IslandView(state: .waiting(count: 7)).frame(width: 440, height: 60)
}

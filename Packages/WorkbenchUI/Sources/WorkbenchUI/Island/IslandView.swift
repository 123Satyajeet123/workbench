import SwiftUI

/// The notch grows ears when a call is recorded or a machine reads, and is not drawn otherwise. The black shape is
/// one piece. Its content is laid out at the open size, so the shape's growth moves no text.
struct IslandView: View {
    let presenter: IslandPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = presenter.metrics
        ZStack(alignment: .top) {
            shape.fill(.black)
                .frame(width: presenter.isOpen ? metrics.openWidth : metrics.notchWidth)
                .opacity(presenter.isDrawn ? 1 : 0)
            ears(metrics)
                .opacity(presenter.isContentVisible ? 1 : 0)
                .accessibilityHidden(!presenter.isContentVisible)
        }
        .frame(width: metrics.panelSize.width, height: metrics.notchHeight, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private func ears(_ metrics: IslandMetrics) -> some View {
        HStack(spacing: 0) {
            Ear { leading }
            Spacer(minLength: 0).frame(width: metrics.notchWidth)
            Ear { trailing }
        }
        .frame(width: metrics.openWidth, height: metrics.notchHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var leading: some View {
        switch presenter.content {
        case .idle: EmptyView()
        case .recording: PulsingDot(isStill: reduceMotion)
        case .reading: SpinningRing(isStill: reduceMotion)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch presenter.content {
        case .idle: EmptyView()
        case .recording(let since): Text(since, style: .timer).monospacedDigit()
        case .reading(let machine): Text(machine).lineLimit(1).truncationMode(.middle)
        }
    }

    private var label: String {
        switch presenter.content {
        case .idle: ""
        case .recording: "Recording a call. Click to open Calls."
        case .reading(let machine): "\(machine) is reading"
        }
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14, style: .continuous)
    }
}

private struct Ear<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .textStyle(.callout, weight: .medium)
            .foregroundStyle(.white)
            .padding(.horizontal, IslandMetrics.earInset)
            .frame(width: IslandMetrics.earWidth)
    }
}

/// A red dot whose brightness rises and falls slowly. Still with Reduce Motion.
private struct PulsingDot: View {
    static let period = 2.4
    static let dimmest = 0.45
    let isStill: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isStill)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate / Self.period * 2 * .pi
            Circle().fill(Tone.bad.color).frame(width: 10, height: 10)
                .opacity(isStill ? 1 : Self.dimmest + (1 - Self.dimmest) * (1 + cos(phase)) / 2)
        }
    }
}

/// A ring with a gap that turns once a second. Still with Reduce Motion.
private struct SpinningRing: View {
    let isStill: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isStill)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            Circle().trim(from: 0, to: 0.75).stroke(.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(isStill ? 0 : turn * 360))
        }
    }
}

#Preview("Recording") {
    IslandView(presenter: IslandPresenter(metrics: .sample, showing: .recording(since: .now.addingTimeInterval(-95))))
        .frame(width: 440, height: 60)
}

#Preview("Reading") {
    IslandView(presenter: IslandPresenter(metrics: .sample, showing: .reading(machine: "Atlas"))).frame(
        width: 440, height: 60)
}

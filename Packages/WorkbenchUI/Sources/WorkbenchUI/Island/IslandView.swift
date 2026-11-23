import SwiftUI

/// The notch grows ears when something shows, and is not drawn otherwise. A hover expands it down to a detail line.
/// The black shape is one piece. Its content is laid out at the open size, so the shape's growth moves no text.
struct IslandView: View {
    let presenter: IslandPresenter
    var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = presenter.metrics
        ZStack(alignment: .top) {
            shape.fill(.black)
                .frame(
                    width: presenter.isOpen ? metrics.openWidth : metrics.notchWidth,
                    height: presenter.isExpanded ? metrics.expandedHeight : metrics.notchHeight
                )
                .opacity(presenter.isDrawn ? 1 : 0)
            VStack(spacing: 0) {
                ears(metrics)
                detail(metrics).opacity(presenter.isDetailVisible ? 1 : 0)
            }
            .opacity(presenter.isContentVisible ? 1 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHidden(!presenter.isContentVisible)
        }
        .frame(
            width: metrics.panelSize.width, height: metrics.panelSize(isTall: presenter.isTall).height,
            alignment: .top
        )
        .scaleEffect(isPressed ? 0.96 : 1, anchor: .top)
        .animation(Motion.snap(reduceMotion: reduceMotion), value: isPressed)
        .environment(\.colorScheme, .dark)
    }

    private func ears(_ metrics: IslandMetrics) -> some View {
        HStack(spacing: 0) {
            Ear { leading }
            Spacer(minLength: 0).frame(width: metrics.notchWidth)
            Ear { trailing }
        }
        .frame(width: metrics.openWidth, height: metrics.notchHeight)
    }

    private func detail(_ metrics: IslandMetrics) -> some View {
        HStack(spacing: Space.s) {
            Text(presenter.content.detail).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            if presenter.content.isRecording {
                Text("Stop").textStyle(.callout, weight: .semibold).foregroundStyle(.white)
                    .frame(width: IslandMetrics.stopSize.width, height: IslandMetrics.stopSize.height)
                    .background(Tone.bad.color, in: .capsule)
            }
        }
        .textStyle(.callout, weight: .medium)
        .padding(.horizontal, IslandMetrics.detailInset)
        .frame(width: metrics.openWidth, height: IslandMetrics.detailHeight)
    }

    @ViewBuilder private var leading: some View {
        switch presenter.content {
        case .idle: EmptyView()
        case .plan(let window): PlanRing(window: window, size: 16)
        case .recording: PulsingDot(isStill: reduceMotion)
        case .reading: SpinningRing(isStill: reduceMotion)
        case .needsYou: Image(systemName: "tray.full.fill").foregroundStyle(Tone.attention.color)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch presenter.content {
        case .idle: EmptyView()
        case .plan(let window): Text(PlanRing.percent(window.used)).monospacedDigit()
        case .recording(let since): Text(since, style: .timer).monospacedDigit()
        case .reading(let names, _):
            Text(IslandState.readingLabel(of: names) ?? "").lineLimit(1).truncationMode(.middle)
        case .needsYou(let machines): Text("\(machines.count)").monospacedDigit()
        }
    }

    private var label: String {
        let content = presenter.content
        return switch content {
        case .idle: ""
        case .plan(let window): "Claude plan \(PlanRing.percent(window.used)) used. Click to open Usage."
        case .recording: "Recording a call. Hover for Stop. Click to open Echo."
        case .reading: "\(content.detail). Click to open."
        case .needsYou: "\(content.detail). Click to open Today."
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

#Preview("Recording, hovered") {
    IslandView(
        presenter: IslandPresenter(
            metrics: .sample, showing: .recording(since: .now.addingTimeInterval(-95)), expanded: true)
    )
    .frame(width: 440, height: 90)
}

#Preview("Reading") {
    IslandView(presenter: IslandPresenter(metrics: .sample, showing: .reading(names: ["Atlas"], page: .crew)))
        .frame(width: 440, height: 60)
}

#Preview("Needs you, hovered") {
    IslandView(
        presenter: IslandPresenter(
            metrics: .sample, showing: .needsYou(machines: ["Pip", "Pip", "Relay"]), expanded: true)
    )
    .frame(width: 440, height: 90)
}

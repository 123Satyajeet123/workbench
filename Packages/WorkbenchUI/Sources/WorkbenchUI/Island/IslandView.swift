import SwiftUI
import WorkbenchCore

struct IslandView: View {
    static let inset: CGFloat = 14
    static let stopSize = CGSize(width: 56, height: 22)
    static let outerPadding: CGFloat = 10
    static let innerPadding: CGFloat = 4

    let state: IslandState
    var metrics = IslandMetrics(screen: nil)
    var isExpanded = false
    var isPressed = false
    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func stopRect(_ metrics: IslandMetrics) -> CGRect {
        CGRect(
            x: metrics.expandedSize.width - inset - stopSize.width,
            y: metrics.notchHeight + (IslandMetrics.detailHeight - stopSize.height) / 2, width: stopSize.width,
            height: stopSize.height)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if state != .idle {
                shape.fill(.black)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ear(.leading, measured: $leadingWidth) { leading }
                        Spacer(minLength: metrics.notchWidth)
                        ear(.trailing, measured: $trailingWidth) { trailing }
                    }
                    .frame(
                        width: metrics.hasNotch ? compact.width : size.width, height: metrics.notchHeight)
                    if isExpanded { detailRow.transition(.opacity.combined(with: .offset(y: -6))) }
                }
                .transition(.opacity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(shape)
        .shadow(color: (tint ?? .white).opacity(isExpanded ? 0.35 : 0), radius: 10)
        .scaleEffect(isPressed ? 0.96 : 1, anchor: .top)
        .environment(\.colorScheme, .dark)
        .animation(spring, value: state)
        .animation(spring, value: isExpanded)
        .animation(.spring(duration: 0.18, bounce: 0.3), value: isPressed)
    }

    private var spring: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.2)
    }

    private var compact: CGSize {
        metrics.compactSize(ear: max(leadingWidth, trailingWidth) + Self.outerPadding + Self.innerPadding)
    }

    private var size: CGSize { isExpanded && state != .idle ? metrics.expandedSize : compact }

    private var shape: UnevenRoundedRectangle {
        let bottom: CGFloat = isExpanded ? 18 : metrics.hasNotch ? 14 : metrics.notchHeight / 2
        let top: CGFloat = metrics.hasNotch ? 0 : bottom
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom, bottomTrailingRadius: bottom, topTrailingRadius: top,
            style: .continuous)
    }

    private var tint: Color? {
        switch state {
        case .idle: nil
        case .plan(let window): PlanRing.tone(of: window)
        case .recording: Tone.bad.color
        case .reading: .accentFill
        case .waiting: Tone.attention.color
        }
    }

    @ViewBuilder private var leading: some View {
        switch state {
        case .idle: EmptyView()
        case .plan(let window): PlanRing(window: window, size: 16)
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
        case .plan(let window): Text(PlanRing.percent(window.used)).monospacedDigit()
        case .recording(let since): Text(since, style: .timer).monospacedDigit()
        case .reading(let names, _):
            Text(names.count == 1 ? Self.short(names[0]) : "\(names.count)")
        case .waiting(let machines): Text("\(machines.count)").monospacedDigit()
        }
    }

    private var detailRow: some View {
        HStack(spacing: Space.s) {
            Text(state.detail).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            if case .recording = state {
                Text("Stop").textStyle(.callout, weight: .semibold).foregroundStyle(.white)
                    .frame(width: Self.stopSize.width, height: Self.stopSize.height)
                    .background(Tone.bad.color, in: .capsule)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .textStyle(.callout, weight: .medium)
        .padding(.horizontal, Self.inset)
        .frame(width: metrics.expandedSize.width, height: IslandMetrics.detailHeight)
    }

    private func ear(
        _ alignment: Alignment, measured: Binding<CGFloat>, @ViewBuilder _ content: () -> some View
    ) -> some View {
        content().textStyle(.callout, weight: .medium).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { measured.wrappedValue = $0 }
            .padding(alignment == .leading ? .leading : .trailing, Self.outerPadding)
            .frame(width: (compact.width - metrics.notchWidth) / 2, alignment: alignment)
    }

    static func short(_ name: String) -> String {
        name.count > 9 ? name.prefix(8).trimmingCharacters(in: .whitespaces) + "…" : name
    }

    private var label: String {
        switch state {
        case .idle: ""
        case .plan(let window): "Claude plan \(PlanRing.percent(window.used)) used. Click for Usage."
        case .recording: "Recording a call. Click to open Echo."
        case .reading: "\(state.detail). Click to open."
        case .waiting: "\(state.detail). Click to review."
        }
    }
}

#Preview("Recording") {
    IslandView(state: .recording(since: .now.addingTimeInterval(-95)), isExpanded: true).frame(width: 440, height: 90)
}

#Preview("Reading") {
    IslandView(state: .reading(names: ["Atlas"], page: .machine(1))).frame(width: 440, height: 60)
}

#Preview("Waiting") {
    IslandView(state: .waiting(machines: ["Pip", "Pip", "Relay"]), isExpanded: true)
        .frame(width: 440, height: 90)
}

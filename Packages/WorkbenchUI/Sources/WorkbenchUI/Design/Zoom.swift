import SwiftUI

/// The app's text size, in fixed steps so every screen can be checked at each. macOS ignores `dynamicTypeSize`
/// (measured: 123×16 pt at every size), so the scale multiplies the text styles' point sizes itself.
struct Zoom: Equatable {
    static let steps: [Double] = [0.85, 1, 1.15, 1.3, 1.5, 1.75]

    let scale: Double

    init(_ scale: Double = 1) {
        self.scale = Self.steps.min { abs($0 - scale) < abs($1 - scale) } ?? 1
    }

    var zoomedIn: Zoom { Zoom(Self.steps.first { $0 > scale } ?? scale) }
    var zoomedOut: Zoom { Zoom(Self.steps.last { $0 < scale } ?? scale) }
    var canZoomIn: Bool { scale < Self.steps.last! }
    var canZoomOut: Bool { scale > Self.steps.first! }

    var controlSize: ControlSize { scale < 1 ? .small : scale >= 1.3 ? .large : .regular }
}

extension EnvironmentValues {
    @Entry var uiScale: Double = 1
}

extension Font.TextStyle {
    var macSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        @unknown default: 13
        }
    }
}

private struct ScaledText: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    let digits: Bool
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View {
        let font = Font.system(
            size: style.macSize * scale, weight: weight ?? (style == .headline ? .semibold : .regular))
        content.font(digits ? font.monospacedDigit() : font)
    }
}

private struct ZoomedWidth: ViewModifier {
    let width: CGFloat
    let alignment: Alignment
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View { content.frame(width: width * scale, alignment: alignment) }
}

extension View {
    /// A fixed width at actual size; the app's zoom scales it, as it scales the text inside.
    func zoomedWidth(_ width: CGFloat, alignment: Alignment = .center) -> some View {
        modifier(ZoomedWidth(width: width, alignment: alignment))
    }

    func textStyle(_ style: Font.TextStyle, weight: Font.Weight? = nil, digits: Bool = false) -> some View {
        modifier(ScaledText(style: style, weight: weight, digits: digits))
    }

    /// The zoom for a whole window: the default text and the size of controls. The window's text and tint come from
    /// the palette here too, so no screen sets them itself.
    func zoomed(_ zoom: Zoom) -> some View {
        textStyle(.body).controlSize(zoom.controlSize).environment(\.uiScale, zoom.scale)
            .foregroundStyle(.bodyText).tint(.accentFill)
    }
}

struct ZoomCommands: Commands {
    @AppStorage("zoom") private var scale = 1.0

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") { scale = Zoom(scale).zoomedIn.scale }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!Zoom(scale).canZoomIn)
            Button("Zoom Out") { scale = Zoom(scale).zoomedOut.scale }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!Zoom(scale).canZoomOut)
            Button("Actual Size") { scale = 1 }
                .keyboardShortcut("0", modifiers: .command)
        }
    }
}

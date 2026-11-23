import AppKit

/// The island's size on a screen with a notch. A screen without a notch has no island.
struct IslandMetrics: Equatable {
    static let earWidth: CGFloat = 84
    /// Between an ear's edge and its content. A name that is wider than the rest truncates in the middle.
    static let earInset: CGFloat = 6
    /// The shape springs a little past its open width; the panel keeps room for it.
    static let overshoot: CGFloat = 4

    static let sample = IslandMetrics(notch: CGSize(width: 221, height: 38))

    let notch: CGSize

    init(notch: CGSize) {
        self.notch = notch
    }

    /// The notch is the gap between the two usable strips beside it. Nil when the screen has no such strips.
    init?(screenWidth: CGFloat, leftStrip: CGRect?, rightStrip: CGRect?, topInset: CGFloat) {
        guard let leftStrip, let rightStrip, topInset > 0 else { return nil }
        self.init(notch: CGSize(width: screenWidth - leftStrip.width - rightStrip.width, height: topInset))
    }

    init?(screen: NSScreen) {
        self.init(
            screenWidth: screen.frame.width, leftStrip: screen.auxiliaryTopLeftArea,
            rightStrip: screen.auxiliaryTopRightArea, topInset: screen.safeAreaInsets.top)
    }

    var notchWidth: CGFloat { notch.width }
    var notchHeight: CGFloat { notch.height }
    var openWidth: CGFloat { notchWidth + 2 * Self.earWidth }
    /// Fixed for the largest state. It holds the shape and nothing else, so a click on it is a click on the island.
    var panelSize: CGSize { CGSize(width: openWidth + 2 * Self.overshoot, height: notchHeight) }

    func panelFrame(on screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - panelSize.width / 2, y: screenFrame.maxY - panelSize.height,
            width: panelSize.width, height: panelSize.height)
    }

    /// The first screen with a notch.
    static var screen: NSScreen? { NSScreen.screens.first { IslandMetrics(screen: $0) != nil } }
}

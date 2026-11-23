import AppKit

/// The island's size on a screen with a notch. A screen without a notch has no island.
struct IslandMetrics: Equatable {
    static let earWidth: CGFloat = 84
    /// Between an ear's edge and its content. A name that is wider than the rest truncates in the middle.
    static let earInset: CGFloat = 6
    /// The shape springs a little past its open size; the panel keeps room for it.
    static let overshoot: CGFloat = 4
    /// The row under the notch that a hover shows.
    static let detailHeight: CGFloat = 34
    /// Between the expanded shape's side and the detail line.
    static let detailInset: CGFloat = 14
    static let actionHeight: CGFloat = 22
    static let actionGap: CGFloat = 8

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
    var expandedHeight: CGFloat { notchHeight + Self.detailHeight }
    var panelSize: CGSize { panelSize(isTall: false) }

    /// It holds the shape and nothing else, so a click on the panel is a click on the island. Tall, it holds the
    /// expanded shape.
    func panelSize(isTall: Bool) -> CGSize {
        CGSize(
            width: openWidth + 2 * Self.overshoot, height: isTall ? expandedHeight + Self.overshoot : notchHeight)
    }

    func panelFrame(on screenFrame: CGRect, isTall: Bool) -> CGRect {
        let size = panelSize(isTall: isTall)
        return CGRect(
            x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height, width: size.width,
            height: size.height)
    }

    /// The buttons of the detail line, laid out from its right edge, in the panel's flipped coordinates.
    func actionRects(_ actions: [IslandAction]) -> [(action: IslandAction, rect: CGRect)] {
        var right = Self.overshoot + openWidth - Self.detailInset
        return actions.map { action in
            let rect = CGRect(
                x: right - action.width, y: notchHeight + (Self.detailHeight - Self.actionHeight) / 2,
                width: action.width, height: Self.actionHeight)
            right = rect.minX - Self.actionGap
            return (action, rect)
        }
    }

    /// The first screen with a notch.
    static var screen: NSScreen? { NSScreen.screens.first { IslandMetrics(screen: $0) != nil } }
}

import AppKit

enum IslandMetrics {
    /// The main screen's notch. A Mac without a notch gets a black notch shape of this size.
    static let notch = NSScreen.main?.notchSize ?? CGSize(width: 221, height: 38)
    static let notchWidth = notch.width
    static let notchHeight = notch.height
    static let earWidth: CGFloat = 64
    /// The clear panel that holds the island; clicks on its clear part go to the app below.
    static let panelSize = CGSize(width: notchWidth + 2 * earWidth + 40, height: notchHeight)
}

extension NSScreen {
    fileprivate var notchSize: CGSize? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

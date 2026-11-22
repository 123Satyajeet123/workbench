import AppKit

struct IslandMetrics: Equatable {
    static let earWidth: CGFloat = 64
    static let defaultNotch = CGSize(width: 221, height: 38)

    let notch: CGSize

    init(screen: NSScreen?) {
        notch = screen?.notchSize ?? Self.defaultNotch
    }

    var notchWidth: CGFloat { notch.width }
    var notchHeight: CGFloat { notch.height }
    var panelSize: CGSize { CGSize(width: notchWidth + 2 * Self.earWidth + 40, height: notchHeight) }

    static var screen: NSScreen? { NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main }
}

extension NSScreen {
    fileprivate var notchSize: CGSize? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

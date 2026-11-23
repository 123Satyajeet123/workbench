import AppKit

struct IslandMetrics: Equatable {
    static let minEar: CGFloat = 32
    static let maxEar: CGFloat = 72
    static let defaultNotch = CGSize(width: 221, height: 38)
    static let pillGap: CGFloat = 8
    static let detailHeight: CGFloat = 34
    static let glow: CGFloat = 12

    let notch: CGSize
    let hasNotch: Bool
    let top: CGFloat

    init(screen: NSScreen?) {
        if let size = screen?.notchSize {
            notch = size
            hasNotch = true
            top = 0
        } else {
            let bar = screen.map { $0.frame.maxY - $0.visibleFrame.maxY } ?? 0
            notch = CGSize(width: Self.pillGap, height: max(bar, 24) - 6)
            hasNotch = false
            top = 3
        }
    }

    var notchWidth: CGFloat { notch.width }
    var notchHeight: CGFloat { notch.height }
    var compactSize: CGSize { compactSize(ear: Self.maxEar) }
    var expandedSize: CGSize {
        CGSize(width: max(compactSize.width + 16, 280), height: notchHeight + Self.detailHeight)
    }

    func compactSize(ear: CGFloat) -> CGSize {
        CGSize(width: notchWidth + 2 * min(max(ear, Self.minEar), Self.maxEar), height: notchHeight)
    }
    var panelSize: CGSize { panelSize(expanded: false) }

    func panelSize(expanded: Bool) -> CGSize {
        CGSize(
            width: expandedSize.width + 2 * Self.glow,
            height: top + (expanded ? expandedSize.height + Self.glow : notchHeight))
    }

    static var screen: NSScreen? { NSScreen.screens.first { $0.notchSize != nil } ?? NSScreen.main }
}

extension NSScreen {
    fileprivate var notchSize: CGSize? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}

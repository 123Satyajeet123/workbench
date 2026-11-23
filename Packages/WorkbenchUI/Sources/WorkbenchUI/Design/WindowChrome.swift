import AppKit
import SwiftUI

struct WindowButtons: Equatable {
    var center: CGFloat
    var trailing: CGFloat

    static let compact = WindowButtons(center: 20, trailing: 72)
    static let hidden = WindowButtons(center: compact.center, trailing: 0)

    static func measure(contentHeight: CGFloat, close: CGRect, zoom: CGRect, inWindow: Bool, isFullScreen: Bool)
        -> WindowButtons
    {
        guard inWindow, !isFullScreen else { return hidden }
        return WindowButtons(center: contentHeight - close.midY, trailing: zoom.maxX)
    }
}

struct WindowChrome: NSViewRepresentable {
    let measured: (WindowButtons) -> Void

    func makeNSView(context: Context) -> NSView { ChromeView(measured: measured) }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class ChromeView: NSView {
        let measured: (WindowButtons) -> Void

        init(measured: @escaping (WindowButtons) -> Void) {
            self.measured = measured
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            if window.toolbar == nil { window.toolbar = NSToolbar(identifier: "workbench.chrome") }
            window.toolbar?.allowsUserCustomization = false
            window.toolbarStyle = .unifiedCompact
            DispatchQueue.main.async { [weak self] in self?.measure() }
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(screenModeChanged), name: name, object: window)
            }
        }

        @objc private func screenModeChanged() { measure() }

        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        private var last: WindowButtons?

        private func measure() {
            guard let window, let content = window.contentView,
                let close = window.standardWindowButton(.closeButton),
                let zoom = window.standardWindowButton(.zoomButton)
            else { return }
            let buttons = WindowButtons.measure(
                contentHeight: content.bounds.height, close: close.convert(close.bounds, to: nil),
                zoom: zoom.convert(zoom.bounds, to: nil), inWindow: close.window === window,
                isFullScreen: window.styleMask.contains(.fullScreen))
            guard buttons != last else { return }
            last = buttons
            measured(buttons)
        }
    }
}

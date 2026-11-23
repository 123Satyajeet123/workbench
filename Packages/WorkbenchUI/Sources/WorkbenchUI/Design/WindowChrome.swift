import AppKit
import SwiftUI

/// Where macOS put the window's close, minimise and zoom buttons, measured from the window's top left corner, so a row
/// beside them can line up with them exactly.
struct WindowButtons: Equatable {
    var center: CGFloat
    var trailing: CGFloat

    /// Where they sit in a unified title bar, until the window is measured.
    static let unified = WindowButtons(center: 26, trailing: 74)
}

/// Gives the main window Notion's title bar. An empty unified toolbar makes the bar 52 pt tall, and macOS then sets the
/// window's buttons in from the corner and centres them in it, as Notion's are; the bar draws no title, no background
/// and no line, so the sidebar and the page show through it. It reports where the buttons ended up.
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
            window.toolbarStyle = .unified
            // The title bar lays its buttons out after this call; measure once it has.
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

        /// The window lays its buttons out again after a resize or full screen; measure again, outside the layout pass.
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
            let closeFrame = close.convert(close.bounds, to: nil)
            let zoomFrame = zoom.convert(zoom.bounds, to: nil)
            let buttons = WindowButtons(center: content.bounds.height - closeFrame.midY, trailing: zoomFrame.maxX)
            guard buttons != last else { return }
            last = buttons
            measured(buttons)
        }
    }
}

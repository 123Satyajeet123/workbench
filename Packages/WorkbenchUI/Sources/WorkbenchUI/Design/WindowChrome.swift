import AppKit
import SwiftUI

struct WindowButtons: Equatable {
    var center: CGFloat
    var trailing: CGFloat

    static let unified = WindowButtons(center: 26, trailing: 74)
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
            window.toolbarStyle = .unified
            DispatchQueue.main.async { [weak self] in self?.measure() }
        }

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

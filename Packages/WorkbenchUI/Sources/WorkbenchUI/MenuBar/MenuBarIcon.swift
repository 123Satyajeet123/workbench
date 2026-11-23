import AppKit
import SwiftUI

/// The menu bar item: the icon, and beside it how many things need the person.
struct MenuBarLabel: View {
    let session: AppSession

    var body: some View {
        let needs = MenuBarNeeds(today: session.today, review: session.review)
        HStack(spacing: 4) {
            MenuBarIcon(capture: session.capture, needs: needs.count)
            if needs.count > 0 { Text("\(needs.count)").monospacedDigit() }
        }
    }
}

struct MenuBarIcon: View {
    let capture: CaptureSettings
    var needs = 0

    static let glyphSize = CGSize(width: 24, height: 18)
    private static let images: [MenuBarGlyph: NSImage] = [
        .off: draw(.off), .capturing: draw(.capturing), .needsYou: draw(.needsYou),
        .recording: NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: nil) ?? NSImage(),
    ]

    var body: some View {
        let glyph = MenuBarGlyph(isRecording: capture.call != nil, needs: needs, status: capture.status)
        Image(nsImage: Self.glyph(glyph)).accessibilityLabel(label(of: glyph))
    }

    static func glyph(_ glyph: MenuBarGlyph) -> NSImage { images[glyph]! }

    private func label(of glyph: MenuBarGlyph) -> String {
        switch glyph {
        case .recording: "Workbench, recording a call"
        case .needsYou: "Workbench, \(needs) \(needs == 1 ? "thing needs" : "things need") you"
        case .capturing, .off: "Workbench, capture \(capture.status.title.lowercased())"
        }
    }

    /// A dot in the top right corner, set off from the glyph by a clear ring.
    private static func drawBadge() {
        let dot = CGRect(x: glyphSize.width - 6.5, y: 0.5, width: 6, height: 6)
        let context = NSGraphicsContext.current?.cgContext
        context?.setBlendMode(.clear)
        NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
        context?.setBlendMode(.normal)
        NSColor.black.setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    private static func draw(_ glyph: MenuBarGlyph) -> NSImage {
        let dimmed = glyph == .off
        let image = NSImage(size: glyphSize, flipped: true) { _ in
            let scale = (glyphSize.width - 2) / 704
            let origin = CGPoint(x: 1, y: (glyphSize.height - 348 * scale) / 2)
            let gap = 1.0
            func shape(_ x: Double, _ y: Double, _ width: Double, _ height: Double, lifted: Bool) -> NSBezierPath {
                let rect = CGRect(
                    x: origin.x + (x - 160) * scale, y: origin.y + (y - 322) * scale, width: width * scale,
                    height: height * scale - (lifted ? gap : 0))
                return NSBezierPath(roundedRect: rect, xRadius: 0.6, yRadius: 0.6)
            }
            NSColor.black.withAlphaComponent(dimmed ? 0.35 : 1).setFill()
            shape(160, 550, 704, 120, lifted: false).fill()
            shape(580, 348, 202, 202, lifted: true).fill()
            NSColor.black.withAlphaComponent(dimmed ? 0.2 : 0.55).setFill()
            shape(222, 438, 298, 112, lifted: true).fill()
            shape(276, 322, 154, 116, lifted: true).fill()
            if glyph == .needsYou { drawBadge() }
            return true
        }
        image.isTemplate = true
        return image
    }
}

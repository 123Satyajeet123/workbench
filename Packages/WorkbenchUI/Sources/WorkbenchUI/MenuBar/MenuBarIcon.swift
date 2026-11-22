import AppKit
import SwiftUI

struct MenuBarIcon: View {
    let capture: CaptureSettings

    static let glyphSize = CGSize(width: 24, height: 18)
    private static let full = draw(dimmed: false)
    private static let dim = draw(dimmed: true)

    var body: some View {
        if capture.call != nil {
            Image(systemName: "record.circle.fill").accessibilityLabel("Workbench, recording a call")
        } else {
            Image(nsImage: Self.glyph(dimmed: capture.status != .capturing))
                .accessibilityLabel("Workbench, capture \(capture.status.title.lowercased())")
        }
    }

    static func glyph(dimmed: Bool) -> NSImage { dimmed ? dim : full }

    private static func draw(dimmed: Bool) -> NSImage {
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
            return true
        }
        image.isTemplate = true
        return image
    }
}

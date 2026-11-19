import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

/// Supporting text must reach 4.5:1 (WCAG AA for text under 18 pt) in light and dark, on the surfaces it sits on.
struct ContrastTests {
    private typealias RGB = (r: Double, g: Double, b: Double)

    private static func resolve(_ color: NSColor, _ name: NSAppearance.Name) -> (rgb: RGB, alpha: Double) {
        var result: (rgb: RGB, alpha: Double) = ((0, 0, 0), 1)
        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB) ?? color
            result = (
                (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)), Double(c.alphaComponent)
            )
        }
        return result
    }

    private static func luminance(_ c: RGB) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    private static func ratio(text: NSColor, opacity: Double, on background: NSColor, _ name: NSAppearance.Name)
        -> Double
    {
        let bg = resolve(background, name).rgb
        let fg = resolve(text, name)
        let a = fg.alpha * opacity
        let blended: RGB = (
            fg.rgb.r * a + bg.r * (1 - a), fg.rgb.g * a + bg.g * (1 - a), fg.rgb.b * a + bg.b * (1 - a)
        )
        let (l1, l2) = (luminance(blended), luminance(bg))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static let surfaces: [NSColor] = [.textBackgroundColor, .windowBackgroundColor]
    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    @Test func supportingTextReaches4Point5OnEverySurface() {
        for name in Self.appearances {
            for surface in Self.surfaces {
                let value = Self.ratio(text: .labelColor, opacity: Color.supportingOpacity, on: surface, name)
                #expect(value >= 4.5, "\(name.rawValue) on \(surface): \(value)")
            }
        }
    }

    @Test func supportingTextReaches4Point5OnTheBlackIsland() {
        let value = Self.ratio(text: .labelColor, opacity: Color.supportingOpacity, on: .black, .darkAqua)
        #expect(value >= 4.5, "island: \(value)")
    }

    @Test func theOldSecondaryTextFailsTheSameCheck() {
        let value = Self.ratio(text: .secondaryLabelColor, opacity: 1, on: .textBackgroundColor, .aqua)
        #expect(value < 4.5, "secondary in light: \(value)")
    }
}

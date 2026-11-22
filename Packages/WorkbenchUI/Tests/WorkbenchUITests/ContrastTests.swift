import AppKit
import SwiftUI
import Testing

@testable import WorkbenchUI

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

    private static func blend(_ top: NSColor, opacity: Double = 1, over base: RGB, _ name: NSAppearance.Name) -> RGB {
        let fg = resolve(top, name)
        let a = fg.alpha * opacity
        return (fg.rgb.r * a + base.r * (1 - a), fg.rgb.g * a + base.g * (1 - a), fg.rgb.b * a + base.b * (1 - a))
    }

    private static func ratio(_ text: NSColor, opacity: Double = 1, on surface: RGB, _ name: NSAppearance.Name)
        -> Double
    {
        let (l1, l2) = (luminance(blend(text, opacity: opacity, over: surface, name)), luminance(surface))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private static func surfaces(_ name: NSAppearance.Name) -> [(String, RGB)] {
        let sidebar = resolve(Palette.sidebar, name).rgb
        return [
            ("page", resolve(Palette.page, name).rgb), ("sidebar", sidebar),
            ("callout", resolve(Palette.callout, name).rgb),
            ("hovered row", blend(Palette.hover, over: sidebar, name)),
            ("selected row", blend(Palette.selected, over: sidebar, name)),
        ]
    }

    @Test func supportingTextReaches4Point5AndBodyText7OnEverySurface() {
        for name in Self.appearances {
            for (surface, rgb) in Self.surfaces(name) {
                let supporting = Self.ratio(Palette.text, opacity: Color.supportingOpacity, on: rgb, name)
                #expect(supporting >= 4.5, "supporting, \(name.rawValue) on \(surface): \(supporting)")
                let body = Self.ratio(Palette.text, on: rgb, name)
                #expect(body >= 7, "body, \(name.rawValue) on \(surface): \(body)")
            }
        }
    }

    @Test func linksAndPrimaryButtonLabelsReach4Point5() {
        for name in Self.appearances {
            for (surface, rgb) in Self.surfaces(name).prefix(3) {
                let link = Self.ratio(Palette.link, on: rgb, name)
                #expect(link >= 4.5, "link, \(name.rawValue) on \(surface): \(link)")
            }
            let label = Self.ratio(.white, on: Self.resolve(Palette.accent, name).rgb, name)
            #expect(label >= 4.5, "white on accent, \(name.rawValue): \(label)")
        }
    }

    @Test func symbolsReach3OnThePageAndTheSidebar() {
        for name in Self.appearances {
            for (surface, rgb) in Self.surfaces(name).prefix(2) {
                let icon = Self.ratio(Palette.icon, on: rgb, name)
                #expect(icon >= 3, "icon, \(name.rawValue) on \(surface): \(icon)")
            }
        }
    }

    @Test func theSidebarsOwnGreysReadOnEveryRow() {
        let texts = [
            ("title", Palette.sidebarText), ("open title", Palette.sidebarSelectedText),
            ("label", Palette.sidebarLabel),
        ]
        for name in Self.appearances {
            for (surface, rgb) in Self.surfaces(name)
            where ["sidebar", "hovered row", "selected row"].contains(surface) {
                for (kind, color) in texts {
                    let value = Self.ratio(color, on: rgb, name)
                    #expect(value >= 4.5, "sidebar \(kind), \(name.rawValue) on \(surface): \(value)")
                }
                let icon = Self.ratio(Palette.sidebarIcon, on: rgb, name)
                #expect(icon >= 3, "sidebar icon, \(name.rawValue) on \(surface): \(icon)")
            }
        }
    }
}

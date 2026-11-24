import AppKit
import SwiftUI

/// The app's colours and body size as the editor takes them: each palette colour resolved for one appearance, as a CSS
/// value, and the size of body text at the app's zoom.
enum EditorTokens {
    static func resolved(for appearance: EditorEnvironment.Appearance, scale: Double) -> [String: String] {
        let colors: [String: NSColor] = [
            "page": Palette.page, "text": Palette.text, "supporting": supporting(), "divider": Palette.divider,
            "hover": Palette.hover, "selected": Palette.selected, "icon": Palette.icon, "accent": Palette.accent,
            "link": Palette.link, "callout": Palette.callout, "good": .systemGreen, "attention": .systemOrange,
            "bad": .systemRed,
        ]
        var tokens = colors.mapValues { css($0, appearance) }
        tokens["body"] = "\(Font.TextStyle.documentBody.macSize * scale)px"
        return tokens
    }

    /// Text beside the main text: the body text at the opacity `ContrastTests` holds above 4.5:1.
    private static func supporting() -> NSColor {
        NSColor(name: "supporting") { appearance in
            let text = Palette.text.resolved(in: appearance)
            return text.withAlphaComponent(text.alphaComponent * Color.supportingOpacity)
        }
    }

    private static func css(_ color: NSColor, _ appearance: EditorEnvironment.Appearance) -> String {
        let value = color.resolved(in: NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)!)
        let channel = { (component: CGFloat) in Int((component * 255).rounded()) }
        return
            "rgba(\(channel(value.redComponent)), \(channel(value.greenComponent)), \(channel(value.blueComponent)), \(String(format: "%.3f", value.alphaComponent)))"
    }
}

extension Font.TextStyle {
    /// The size of the words of a page that is written in: the app's `title3`, so the page reads as one with its header.
    static let documentBody = Font.TextStyle.title3
}

extension NSColor {
    fileprivate func resolved(in appearance: NSAppearance) -> NSColor {
        var resolved = self
        appearance.performAsCurrentDrawingAppearance { resolved = usingColorSpace(.sRGB) ?? self }
        return resolved
    }
}

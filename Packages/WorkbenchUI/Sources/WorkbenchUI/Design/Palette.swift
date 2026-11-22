import AppKit
import SwiftUI

enum Palette {
    static let page = dynamic("page", light: rgb(0xFFFFFF), dark: rgb(0x191919))
    static let sidebar = dynamic("sidebar", light: rgb(0xF7F7F5), dark: rgb(0x202020))
    static let callout = dynamic("callout", light: rgb(0xF1F1EF), dark: rgb(0x252525))
    static let text = dynamic("text", light: rgb(0x37352F), dark: .white.withAlphaComponent(0.81))
    static let hover = dynamic("hover", light: rgb(0x37352F, alpha: 0.04), dark: .white.withAlphaComponent(0.035))
    static let selected = dynamic("selected", light: rgb(0x37352F, alpha: 0.06), dark: .white.withAlphaComponent(0.055))
    /// The sidebar's own warm greys, measured from Notion's: its rows are dimmer than page text and brighten when
    /// selected. Its labels and counts are a step lighter than Notion's, which read only 4.1:1, so they still read
    /// 4.5:1 on a selected row.
    static let sidebarText = dynamic("sidebarText", light: rgb(0x5F5E5B), dark: rgb(0xBDBBB7))
    static let sidebarSelectedText = dynamic("sidebarSelectedText", light: rgb(0x37352F), dark: rgb(0xEEEDEB))
    static let sidebarIcon = dynamic("sidebarIcon", light: rgb(0x6E6D69), dark: rgb(0xADA9A4))
    static let sidebarLabel = dynamic("sidebarLabel", light: rgb(0x6B6A66), dark: rgb(0x96938E))
    static let divider = dynamic("divider", light: rgb(0x37352F, alpha: 0.09), dark: .white.withAlphaComponent(0.094))
    static let icon = dynamic("icon", light: rgb(0x37352F, alpha: 0.6), dark: .white.withAlphaComponent(0.5))
    static let accent = dynamic("accent", light: rgb(0x1C6BC0), dark: rgb(0x1E70C9))
    static let link = dynamic("link", light: rgb(0x1C6BC0), dark: rgb(0x529CCA))

    private static func rgb(_ hex: Int, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func dynamic(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}

extension ShapeStyle where Self == Color {
    static var pageFill: Color { Color(nsColor: Palette.page) }
    static var sidebarFill: Color { Color(nsColor: Palette.sidebar) }
    static var calloutFill: Color { Color(nsColor: Palette.callout) }
    static var bodyText: Color { Color(nsColor: Palette.text) }
    static var hoverFill: Color { Color(nsColor: Palette.hover) }
    static var selectedFill: Color { Color(nsColor: Palette.selected) }
    static var dividerLine: Color { Color(nsColor: Palette.divider) }
    static var iconTint: Color { Color(nsColor: Palette.icon) }
    static var sidebarText: Color { Color(nsColor: Palette.sidebarText) }
    static var sidebarSelectedText: Color { Color(nsColor: Palette.sidebarSelectedText) }
    static var sidebarIcon: Color { Color(nsColor: Palette.sidebarIcon) }
    static var sidebarLabel: Color { Color(nsColor: Palette.sidebarLabel) }
    static var accentFill: Color { Color(nsColor: Palette.accent) }
    static var linkText: Color { Color(nsColor: Palette.link) }
}

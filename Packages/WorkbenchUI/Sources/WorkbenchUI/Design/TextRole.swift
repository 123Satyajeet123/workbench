import SwiftUI

/// What a piece of text is for. A role fixes its size, weight and colour, so no page picks them again.
enum TextRole: CaseIterable {
    case pageTitle, sectionTitle, rowTitle, meta, quote, caption

    var style: Font.TextStyle {
        switch self {
        case .pageTitle: .largeTitle
        case .sectionTitle: .headline
        case .rowTitle, .quote: .body
        case .meta: .callout
        case .caption: .subheadline
        }
    }

    var weight: Font.Weight {
        switch self {
        case .pageTitle: .bold
        case .sectionTitle: .semibold
        case .rowTitle: .medium
        case .meta, .quote, .caption: .regular
        }
    }

    /// Text beside the main text. `ContrastTests` holds the supporting colour above 4.5:1 on every surface.
    var isSupporting: Bool { self == .meta || self == .caption }

    var isItalic: Bool { self == .quote }
}

private struct RoleText: ViewModifier {
    let role: TextRole

    func body(content: Content) -> some View {
        content
            .textStyle(role.style, weight: role.weight)
            .italic(role.isItalic)
            .foregroundStyle(role.isSupporting ? Color.supporting : Color.bodyText)
    }
}

extension View {
    /// The size, weight and colour of a text role, scaled by the app's zoom.
    func text(_ role: TextRole) -> some View {
        modifier(RoleText(role: role))
    }
}

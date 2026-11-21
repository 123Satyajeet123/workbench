import SwiftUI

/// The spacing scale. Every gap and padding in the app is one of these.
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 20
    static let xl: CGFloat = 32
    static let page: CGFloat = 40
}

enum Radius {
    static let card: CGFloat = 8
    static let control: CGFloat = 6
}

/// What a status means, as one colour each.
enum Tone {
    case good, attention, bad, neutral

    var color: Color {
        switch self {
        case .good: .green
        case .attention: .orange
        case .bad: .red
        case .neutral: .supporting
        }
    }
}

extension ShapeStyle where Self == Color {
    /// The opacity of the body text used for supporting text. `ContrastTests` holds it above 4.5:1 on every surface.
    static var supportingOpacity: Double { 0.72 }

    /// Text beside the main text. `.secondary` measures 3.9:1 on white; this stays above 4.5:1 in both appearances.
    static var supporting: Color { Color.bodyText.opacity(supportingOpacity) }
}

/// A page of the main window, laid out as Notion lays out a page: the helper's face above a large title, a quiet line
/// under it, and the content in one readable column.
struct Page<Content: View, Accessory: View>: View {
    static var columnWidth: CGFloat { 760 }

    let title: String
    var subtitle: String?
    var look: Mascot.Look?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let look { Mascot(look: look, size: 52) }
                    HStack(alignment: .center, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(title).textStyle(.largeTitle, weight: .bold)
                            if let subtitle { Text(subtitle).foregroundStyle(.supporting) }
                        }
                        Spacer()
                        accessory
                    }
                }
                content
            }
            .frame(maxWidth: Self.columnWidth, alignment: .leading)
            .padding(Space.page)
            .frame(maxWidth: .infinity)
        }
        .background(.pageFill)
    }
}

extension Page where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, look: Mascot.Look? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, look: look, accessory: { EmptyView() }, content: content)
    }
}

/// A titled block on a page, with a symbol or a helper's face beside the title.
struct Card<Icon: View, Content: View>: View {
    let title: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label {
                Text(title)
            } icon: {
                icon.foregroundStyle(.iconTint)
            }.textStyle(.headline)
            content
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }
}

extension Card where Icon == Image {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: { Image(systemName: symbol) }, content: content)
    }
}

/// A plain-words problem with a way to dismiss it.
struct ProblemBanner: View {
    let text: String
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(Tone.bad.color)
                .textSelection(.enabled)
            Spacer()
            if let dismiss { Button("Dismiss", action: dismiss).buttonStyle(.ghost) }
        }
        .textStyle(.callout)
    }
}

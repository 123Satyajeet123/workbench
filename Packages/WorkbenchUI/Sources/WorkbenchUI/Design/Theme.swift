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
    static let card: CGFloat = 12
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
    /// The opacity of primary text used for supporting text. `ContrastTests` holds it above 4.5:1.
    static var supportingOpacity: Double { 0.72 }

    /// Text beside the main text. `.secondary` measures 3.9:1 on white; this stays above 4.5:1 in both appearances.
    static var supporting: Color { Color.primary.opacity(supportingOpacity) }
}

/// A page of the main window: a title, an optional face and line under it, and its content in one readable column.
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
                HStack(alignment: .center, spacing: Space.m) {
                    if let look { Mascot(look: look, size: 52) }
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(title).font(.largeTitle.bold())
                        if let subtitle { Text(subtitle).foregroundStyle(.supporting) }
                    }
                    Spacer()
                    accessory
                }
                content
            }
            .frame(maxWidth: Self.columnWidth, alignment: .leading)
            .padding(Space.page)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                icon
            }.font(.headline)
            content
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
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
            if let dismiss { Button("Dismiss", action: dismiss).buttonStyle(.borderless) }
        }
        .font(.callout)
    }
}

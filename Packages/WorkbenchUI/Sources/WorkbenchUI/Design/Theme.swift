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
/// under it, and the content in one readable column. A sidebar page opens with a short note on what it is for, until
/// the person closes it; then an ⓘ beside the title shows it again.
struct Page<Content: View, Accessory: View>: View {
    static var columnWidth: CGFloat { 760 }

    /// The sidebar page this is, for its introduction; nil for a page with none.
    var intro: SidebarSelection?
    let title: String
    var subtitle: String?
    var look: Mascot.Look?
    @ViewBuilder let accessory: Accessory
    @ViewBuilder let content: Content
    @AppStorage(DismissedIntros.key) private var dismissed = DismissedIntros()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.m) {
                    if let look { Mascot(look: look, size: 52) }
                    HStack(alignment: .center, spacing: Space.m) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            HStack(alignment: .center, spacing: Space.xs) {
                                Text(title).textStyle(.largeTitle, weight: .bold)
                                if let intro, intro.intro != nil, dismissed.contains(intro) {
                                    PageIntroButton { setDismissed(false, intro) }
                                }
                            }
                            if let subtitle { Text(subtitle).foregroundStyle(.supporting) }
                        }
                        Spacer()
                        accessory
                    }
                    if let intro, let text = intro.intro, !dismissed.contains(intro) {
                        PageIntroCallout(text: text) { setDismissed(true, intro) }
                            .transition(.opacity)
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

    private func setDismissed(_ isDismissed: Bool, _ page: SidebarSelection) {
        withAnimation(Motion.settle(reduceMotion: reduceMotion)) {
            if isDismissed { dismissed.dismiss(page) } else { dismissed.restore(page) }
        }
    }
}

extension Page where Accessory == EmptyView {
    init(
        intro: SidebarSelection? = nil, title: String, subtitle: String? = nil, look: Mascot.Look? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            intro: intro, title: title, subtitle: subtitle, look: look, accessory: { EmptyView() }, content: content)
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
        .calloutBox(padding: Space.l, fillsWidth: true)
    }
}

extension Card where Icon == Image {
    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, icon: { Image(systemName: symbol) }, content: content)
    }
}

extension View {
    @ViewBuilder func calloutBox(padding: CGFloat = Space.m, fillsWidth: Bool = false) -> some View {
        if fillsWidth {
            self.padding(padding).frame(maxWidth: .infinity, alignment: .leading).calloutFill()
        } else {
            self.padding(padding).calloutFill()
        }
    }

    func pill(_ fill: some ShapeStyle = .quaternary) -> some View {
        textStyle(.caption).padding(.horizontal, Space.s).padding(.vertical, 2).background(fill, in: .capsule)
    }

    private func calloutFill() -> some View { background(.calloutFill, in: .rect(cornerRadius: Radius.card)) }
}

/// A plain-words problem with a way to dismiss it.
struct ProblemBanner: View {
    let text: String
    var dismiss: (() -> Void)?
    var settingsPane: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Tone.bad.color)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                    message.fixedSize()
                    Spacer(minLength: 0)
                    actions
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    message.fixedSize(horizontal: false, vertical: true)
                    actions.padding(.leading, settingsPane == nil ? -Space.s : 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .calloutBox()
        .textStyle(.callout)
    }

    private var message: some View {
        Text(text).foregroundStyle(Tone.bad.color).textSelection(.enabled)
    }

    @ViewBuilder private var actions: some View {
        if settingsPane != nil || dismiss != nil {
            HStack(spacing: Space.xs) {
                if let settingsPane {
                    Button("Open System Settings") { SystemSettings.open(pane: settingsPane) }.buttonStyle(.primary)
                }
                if let dismiss { Button("Dismiss", action: dismiss).buttonStyle(.ghost) }
            }
        }
    }
}

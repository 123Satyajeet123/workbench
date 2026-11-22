import LocalSources
import SwiftUI

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
    static var supportingOpacity: Double { 0.72 }

    static var supporting: Color { Color.bodyText.opacity(supportingOpacity) }
}

struct Page<Content: View, Accessory: View>: View {
    static var columnWidth: CGFloat { 760 }

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

    private func calloutFill() -> some View { background(.calloutFill, in: .rect(cornerRadius: Radius.card)) }
}

struct ProblemSlotBanner: View {
    let slot: ProblemSlot

    var body: some View {
        if let text = slot.text {
            ProblemBanner(text: text, dismiss: slot.dismiss, settingsPane: slot.settingsPane)
        }
    }
}

struct ProblemBanner: View {
    let text: String
    var dismiss: (() -> Void)?
    var settingsPane: PrivacyPane?

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

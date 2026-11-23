import SwiftUI
import WorkbenchCore

/// One fact as one row of fixed height: the person and their quote, and under it where and when it was said and its due
/// day. The actions take the place on the right under the pointer or on the selected row; the row does not change size.
struct FactCard: View {
    let row: FactRow
    /// The verdict of a claim check: its mark takes the place of the person's letter.
    var verdict: ClaimVerdict?
    let offered: [FactAction]
    var isSelected = false
    var isHovered = false
    /// The action the row confirms before it leaves.
    var confirming: FactAction?
    var now: Date = .now
    let hover: (Bool) -> Void
    let open: () -> Void
    let act: (FactAction) -> Void

    @Environment(\.uiScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var today: WorkDay { WorkDay(containing: now) }
    private var showsBar: Bool { (isHovered || isSelected) && confirming == nil }

    var body: some View {
        HStack(spacing: Space.m) {
            person
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                row.headline.text.textStyle(.body).foregroundStyle(.bodyText).lineLimit(1).truncationMode(.tail)
                line.text(.meta).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
            trailing
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(fill, in: .rect(cornerRadius: Radius.card))
        .contentShape(.rect(cornerRadius: Radius.card))
        .onHover(perform: hover)
        .onTapGesture(perform: open)
        .animation(Motion.reveal(reduceMotion: reduceMotion), value: showsBar)
        .animation(Motion.snap(reduceMotion: reduceMotion), value: isSelected)
        .animation(Motion.snap(reduceMotion: reduceMotion), value: confirming)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(row.spoken(now: now))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            ForEach(offered, id: \.self) { action in
                Button(action.title) { act(action) }
            }
        }
    }

    private var fill: Color {
        if let confirming { return confirming.tone.color.opacity(Self.confirmationOpacity) }
        if isSelected { return .selectedFill }
        return isHovered ? .hoverFill : .clear
    }

    @ViewBuilder private var person: some View {
        let size = Self.personSize * scale
        if let verdict {
            Image(systemName: verdict.symbol).fontWeight(.semibold).foregroundStyle(verdict.tone.color)
                .frame(width: size, height: size)
                .background(.selectedFill, in: .rect(cornerRadius: size * 0.3)).accessibilityHidden(true)
        } else if row.headline.person.isEmpty {
            Image(systemName: "text.quote").foregroundStyle(.supporting).frame(width: size, height: size)
                .background(.selectedFill, in: .rect(cornerRadius: size * 0.3)).accessibilityHidden(true)
        } else {
            Monogram(name: row.headline.person, size: size)
        }
    }

    private var line: Text {
        let said = Text(verbatim: row.said(now: now))
        guard let due = row.due(today: today) else { return said }
        let day =
            due.tone == .neutral
            ? Text(verbatim: due.text)
            : Text(verbatim: due.text).foregroundStyle(due.tone.color.mix(with: .bodyText, by: Self.dueTextMix))
        return Text("\(said) · \(day)")
    }

    /// The bar, and the confirmation: both in one place, so the row keeps its size.
    private var trailing: some View {
        ZStack(alignment: .trailing) {
            MarkBar(actions: offered, act: act)
                .opacity(showsBar ? 1 : 0)
                .allowsHitTesting(showsBar)
                .accessibilityHidden(true)
            if let confirming {
                Image(systemName: confirming.confirmedSymbol).foregroundStyle(confirming.tone.color)
                    .textStyle(.body).transition(.opacity)
            }
        }
    }

    /// How much of the body colour the due day takes, so a tone reads on the page in light and dark.
    static let dueTextMix = 0.3

    /// A light tint of the action's tone; a strong fill would flash.
    static let confirmationOpacity = 0.1
    static let personSize: CGFloat = 22
}

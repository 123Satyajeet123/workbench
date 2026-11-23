import SwiftUI
import WorkbenchCore

/// One fact as one row of fixed height: the person, the title, a line of facts about it, and on the right its due day
/// and why it is here. The actions take the place of the right side under the pointer or on the selected row; the row
/// does not change size.
struct FactCard: View {
    let row: FactRow
    let offered: [FactAction]
    var isSelected = false
    var isHovered = false
    /// The action the row confirms before it leaves.
    var confirming: FactAction?
    var now: Date = .now
    let hover: (Bool) -> Void
    let open: () -> Void
    let act: (FactAction) -> Void

    @State private var isChoosing = false
    @Environment(\.uiScale) private var scale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var today: WorkDay { WorkDay(containing: now) }
    private var showsBar: Bool { (isHovered || isSelected || isChoosing) && confirming == nil }

    var body: some View {
        HStack(spacing: Space.m) {
            person
            VStack(alignment: .leading, spacing: Space.xs / 2) {
                Text(row.title).text(.rowTitle).lineLimit(1).truncationMode(.tail)
                Text(row.meta(now: now)).text(.meta).lineLimit(1).truncationMode(.tail)
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
        .accessibilityLabel(row.spoken(today: today))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            ForEach(offered, id: \.self) { action in
                Button(action.title) { act(action) }
            }
        }
    }

    private var fill: Color {
        if let confirming { return confirming.tone.color.opacity(Chip.fillOpacity) }
        if isSelected { return .selectedFill }
        return isHovered ? .hoverFill : .clear
    }

    @ViewBuilder private var person: some View {
        let size = Self.personSize * scale
        if row.person.isEmpty {
            Image(systemName: "text.quote").foregroundStyle(.supporting).frame(width: size, height: size)
                .background(.selectedFill, in: .rect(cornerRadius: size * 0.3)).accessibilityHidden(true)
        } else {
            Monogram(name: row.person, size: size)
        }
    }

    /// The due day and the reason, the bar, and the confirmation: all in one place, so the row keeps its size.
    private var trailing: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: Space.s) {
                if let due = row.due(today: today) {
                    HStack(spacing: Space.xs) {
                        if due.tone != .neutral { Circle().fill(due.tone.color).frame(width: 6, height: 6) }
                        Text(due.text).text(.meta).monospacedDigit()
                    }
                }
                if let reason = row.reason { Chip(reason.text, tone: reason.tone) }
            }
            .opacity(showsBar || confirming != nil ? 0 : 1)
            MarkBar(actions: offered, isChoosing: $isChoosing, act: act)
                .opacity(showsBar ? 1 : 0)
                .allowsHitTesting(showsBar)
                .accessibilityHidden(true)
            if let confirming {
                Image(systemName: confirming.confirmedSymbol).foregroundStyle(confirming.tone.color)
                    .textStyle(.body).transition(.opacity)
            }
        }
    }

    static let personSize: CGFloat = 22
}

import SwiftUI

/// A list on a card where the person picks one item: each row has a radio mark, then the item's own label.
struct ChoiceList<Item: Identifiable & Equatable, Label: View>: View {
    let items: [Item]
    @Binding var chosen: Item?
    @ViewBuilder let label: (Item) -> Label

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                row(item)
                if item != items.last { Divider() }
            }
        }
        .padding(.horizontal, Space.m)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }

    private func row(_ item: Item) -> some View {
        let isChosen = item == chosen
        return Button {
            chosen = item
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isChosen ? Color.accentFill : Color.bodyText.opacity(0.4))
                label(item)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.m)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }
}

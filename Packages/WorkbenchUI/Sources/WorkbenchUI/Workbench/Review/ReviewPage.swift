import SwiftUI
import WorkbenchCore

/// The one place to check what the crew found. Y marks right, N wrong, J and K move, U takes the last mark back.
struct ReviewPage: View {
    @Environment(ReviewModel.self) private var review
    @FocusState private var focused: Bool

    var body: some View {
        Page(intro: .review, title: SidebarSelection.review.title, subtitle: subtitle) {
            if let problem = review.problem { ProblemBanner(text: problem) }
            if review.items.isEmpty {
                Text("Nothing waits for you. When a machine reads a day, what it finds appears here.")
                    .foregroundStyle(.supporting)
            }
            ForEach(Array(review.items.enumerated()), id: \.element.id) { index, item in
                ReviewRow(item: item, isSelected: index == review.selected)
                    .contentShape(.rect)
                    .onTapGesture { review.select(index) }
            }
            if review.canUndo { Button("Undo last mark (U)", action: review.undo).buttonStyle(.ghost) }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(characters: .init(charactersIn: "ynjkuYNJKU")) { press in
            switch press.characters.lowercased() {
            case "y": review.mark(.confirmed)
            case "n": review.mark(.rejected)
            case "j": review.next()
            case "k": review.previous()
            case "u": review.undo()
            default: return .ignored
            }
            return .handled
        }
        .onAppear {
            review.refresh()
            focused = true
        }
    }

    private var subtitle: String {
        "\(review.items.count) waiting, \(review.questions) picked at random, from the last \(ReviewModel.days) days. Y right · N wrong · J/K move · U undo."
    }
}

private struct ReviewRow: View {
    let item: Item
    let isSelected: Bool
    @Environment(ReviewModel.self) private var review

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            if let helper = review.helper(for: item) {
                Mascot(look: .of(helper.machine), size: 22, mood: helper.mood)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(title).fontWeight(.medium)
                    if item.askedWith != nil {
                        Text("Picked at random").textStyle(.caption).padding(.horizontal, Space.s).padding(.vertical, 2)
                            .background(Tone.attention.color.opacity(0.2), in: .capsule)
                    }
                }
                Text("“\(item.quote)”").textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                Text(origin).textStyle(.caption).foregroundStyle(.supporting)
            }
            Spacer()
            MarkButtons(state: item.state) { mark in
                review.select(review.items.firstIndex(of: item) ?? 0)
                review.mark(mark)
            }
        }
        .padding(Space.s)
        .background(isSelected ? Color.selectedFill : .clear, in: .rect(cornerRadius: Radius.card))
    }

    private var title: String {
        guard let spec = review.helper(for: item)?.spec else { return item.quote }
        return item[spec.title]
    }

    private var origin: String {
        let name = review.name(of: item)
        return
            "\(name) · \(item.day.start.formatted(.dateTime.weekday(.wide).day().month())) · \(item.start.formatted(date: .omitted, time: .shortened))"
    }
}

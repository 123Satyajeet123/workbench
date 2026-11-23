import SwiftUI

/// ⌘K: one field and a list under it, over the window. Keys only: ↑ and ↓ move, Return runs, Esc goes back or closes.
struct PaletteView: View {
    let commands: [PaletteEntry]
    let facts: [PaletteEntry]
    let callChoices: [PaletteEntry]
    let run: (PaletteEntry.Action) -> Void
    let close: () -> Void

    private enum Step { case search, call }

    @State private var query = ""
    @State private var step = Step.search
    @State private var highlighted = 0
    @FocusState private var isFocused: Bool
    @Environment(\.uiScale) private var scale

    private var results: [PaletteEntry] {
        step == .call
            ? PaletteSearch.results(for: query, commands: callChoices, facts: [])
            : PaletteSearch.results(for: query, commands: commands, facts: facts)
    }

    var body: some View {
        VStack(spacing: 0) {
            field
            Divider()
            list
        }
        .frame(width: 560 * scale)
        .background(.regularMaterial, in: .rect(cornerRadius: Radius.card * 2))
        .overlay(RoundedRectangle(cornerRadius: Radius.card * 2).strokeBorder(.dividerLine))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
        .onAppear { isFocused = true }
        .onChange(of: query) { highlighted = 0 }
        .accessibilityAddTraits(.isModal)
    }

    private var field: some View {
        HStack(spacing: Space.s) {
            Image(systemName: step == .call ? "record.circle" : "magnifyingglass").foregroundStyle(.supporting)
            TextField(
                step == .call ? "Which app is the call in?" : "Go to, or find a fact", text: $query
            )
            .textFieldStyle(.plain)
            .textStyle(.title3)
            .focused($isFocused)
            .onSubmit(runHighlighted)
            .onKeyPress(.upArrow) { move(-1) }
            .onKeyPress(.downArrow) { move(1) }
            .onExitCommand(perform: back)
        }
        .padding(Space.m)
    }

    private var list: some View {
        let rows = results
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        PaletteRow(entry: entry, isHighlighted: index == highlighted).id(index)
                    }
                    if rows.isEmpty { Text("Nothing matches.").text(.meta).padding(Space.m) }
                }
                .padding(Space.xs)
            }
            .frame(maxHeight: 340 * scale)
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
    }

    private func move(_ offset: Int) -> KeyPress.Result {
        let count = results.count
        guard count > 0 else { return .handled }
        highlighted = max(0, min(highlighted + offset, count - 1))
        return .handled
    }

    private func runHighlighted() {
        let rows = results
        guard rows.indices.contains(highlighted) else { return }
        if rows[highlighted].action == .chooseCall {
            step = .call
            query = ""
        } else {
            run(rows[highlighted].action)
            close()
        }
    }

    private func back() {
        if step == .call {
            step = .search
            query = ""
        } else {
            close()
        }
    }
}

private struct PaletteRow: View {
    let entry: PaletteEntry
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: entry.symbol).frame(width: 20).foregroundStyle(.supporting)
            Text(entry.title).lineLimit(1)
            if let detail = entry.detail { Text(detail).text(.meta).lineLimit(1) }
            Spacer(minLength: Space.s)
            if let shortcut = entry.shortcut { KeyHint(shortcut) }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.s)
        .background(isHighlighted ? Color.selectedFill : .clear, in: .rect(cornerRadius: Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

import SwiftUI
import WorkbenchCore

/// A row that leaves: it fades while its height closes, so the rows below close the gap.
private struct Collapse: Layout {
    var openness: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews[0].sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height * openness)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

/// A list of facts with keys, a selection, a cap and slots for an empty list and for the end of one. Facts come in as
/// rows; a person acts on one at a time, and the row confirms and leaves.
struct FactList<Empty: View, Closing: View>: View {
    let rows: [FactRow]
    let acting: any FactActing
    let surface: Surface
    let selection: FactSelection
    let toast: ToastCenter
    /// How many rows show before "Show more".
    var limit = 8
    var now: Date = .now
    @ViewBuilder let empty: Empty
    @ViewBuilder let closing: Closing

    @State private var flow = FactFlow()
    @State private var displayed: [FactRow]
    @State private var showsAll = false
    @State private var hovered: Int64?
    @FocusState private var isFocused: Bool
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        rows: [FactRow], acting: any FactActing, surface: Surface, selection: FactSelection, toast: ToastCenter,
        limit: Int = 8, now: Date = .now, @ViewBuilder empty: () -> Empty, @ViewBuilder closing: () -> Closing
    ) {
        self.rows = rows
        self.acting = acting
        self.surface = surface
        self.selection = selection
        self.toast = toast
        self.limit = limit
        self.now = now
        self.empty = empty()
        self.closing = closing()
        _displayed = State(initialValue: rows)
    }

    private var visible: [FactRow] { displayed.capped(at: limit, showingAll: showsAll).shown }
    private var hiddenCount: Int { displayed.capped(at: limit, showingAll: showsAll).hidden }
    private var selectedRow: FactRow? { visible.first { $0.id == selection.selected } }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 2) {
                if displayed.isEmpty {
                    empty
                } else {
                    ForEach(visible) { row in
                        leaving(row).id(row.id).transition(.opacity)
                    }
                    if hiddenCount > 0 {
                        Button("Show \(hiddenCount) more") { showsAll = true }.buttonStyle(.ghost)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.s)
                    } else {
                        closing
                    }
                }
            }
            .animation(Motion.settle(reduceMotion: reduceMotion), value: visible.map(\.id))
            .animation(Motion.settle(reduceMotion: reduceMotion), value: showsAll)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress(phases: [.down, .repeat], action: handle)
            .onChange(of: rows) { _, _ in syncRows() }
            .onChange(of: flow.held) { _, _ in syncRows() }
            .onChange(of: selection.selected) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private func leaving(_ row: FactRow) -> some View {
        let isLeaving = flow.leaving.contains(row.id)
        return Collapse(openness: isLeaving ? 0 : 1) {
            card(row).opacity(isLeaving ? 0 : 1)
        }
        .clipped()
        .animation(Motion.settle(reduceMotion: reduceMotion), value: isLeaving)
    }

    private func card(_ row: FactRow) -> some View {
        FactCard(
            row: row, offered: acting.offered(for: row.item), isSelected: selection.selected == row.id,
            isHovered: hovered == row.id, confirming: flow.confirming[row.id], now: now,
            hover: { isInside in hovered = isInside ? row.id : (hovered == row.id ? nil : hovered) },
            open: {
                isFocused = true
                selection.select(row.item)
                selection.inspectSelected(in: visible.map(\.item))
            },
            act: { action in
                selection.select(row.item)
                perform(action, on: row)
            })
    }

    private func syncRows() {
        let incoming = Set(rows.map(\.id))
        for row in displayed where !incoming.contains(row.id) && !flow.held.contains(row.id) {
            flow.retire(row.id)
        }
        displayed = displayed.displayed(replacing: rows, keeping: flow.held)
    }

    private func perform(_ action: FactAction, on row: FactRow) {
        let context = FactContext(
            acting: acting, surface: surface, selection: selection, toast: toast, undoManager: undoManager,
            items: visible.map(\.item))
        Task { await flow.run(action, on: row, in: context) }
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let offered = selectedRow.map { acting.offered(for: $0.item) } ?? []
        guard let command = FactKeys.command(for: press.key, modifiers: press.modifiers, offered: offered) else {
            return .ignored
        }
        switch command {
        case .move(let offset): selection.move(by: offset, in: visible.map(\.item))
        case .act(let action): if let row = selectedRow { perform(action, on: row) }
        case .inspect: selection.inspectSelected(in: visible.map(\.item))
        case .closeInspector: return selection.closeInspector() ? .handled : .ignored
        }
        return .handled
    }
}

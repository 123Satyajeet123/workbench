import SwiftUI
import WorkbenchCore

/// The window's one right panel: the chosen fact with its proof, or the Playbook of the open page.
struct PanelView: View {
    let content: PanelContent
    @Environment(FactSelection.self) private var selection
    @Environment(PlaybookSlot.self) private var playbook

    var body: some View {
        Group {
            switch content {
            case .fact:
                InspectorView(item: selection.inspected) {
                    if let item = selection.inspected { PanelMarkBar(item: item) }
                }
            case .playbook:
                playbook.content?()
            case .hidden:
                EmptyView()
            }
        }
        .inspectorColumnWidth(min: InspectorView<EmptyView>.widths.lowerBound, ideal: 360, max: 420)
        .onExitCommand { _ = selection.closeInspector() }
    }
}

/// The actions of the fact in the panel. They run through the page's own acting, the window's undo and its toast, as a
/// list's do.
private struct PanelMarkBar: View {
    let item: Item
    @Environment(\.factActing) private var acting
    @Environment(\.factSurface) private var surface
    @Environment(FactSelection.self) private var selection
    @Environment(ToastCenter.self) private var toast
    @Environment(TodayModel.self) private var today
    @Environment(\.undoManager) private var undoManager
    @State private var flow = FactFlow()

    var body: some View {
        if let acting {
            MarkBar(actions: acting.offered(for: item)) { action in
                guard let row = FactRow(item: item, title: today.title(of: item)) else { return }
                let context = FactContext(
                    acting: acting, surface: surface, selection: selection, toast: toast, undoManager: undoManager,
                    items: [item])
                Task { await flow.run(action, on: row, in: context) }
            }
        }
    }
}

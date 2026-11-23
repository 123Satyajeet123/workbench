import SwiftUI
import WorkbenchCore

/// One block of a machine, drawn by its kind. A block the person may still remove has a control that shows on hover
/// or keyboard focus. A block of a pending proposal says how it stands, in words as well as in its look.
struct MachineBlockView: View {
    let model: MachinePageModel
    let id: MachineBlockID
    let shown: ShownBlock
    @State private var isHovered = false
    @FocusState private var removeHasFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let standing = standingWords { Text(standing).text(.meta) }
            content
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight, in: .rect(cornerRadius: Radius.card))
        .padding(-Space.s)
        .strikethrough(shown.standing == .removed)
        .opacity(shown.standing == .removed ? 0.6 : 1)
        .overlay(alignment: .topTrailing) { if shown.standing == .live { removeControl } }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var content: some View {
        if shown.isErased {
            Text("The message this came from was deleted").text(.meta)
        } else {
            switch shown.block {
            case .heading(let words):
                Text(words).textStyle(.title3, weight: .semibold).accessibilityAddTraits(.isHeader)
            case .text(let cited): CitedTextView(model: model, text: cited)
            case .facts(let view): FactsBlockView(model: model, view: view)
            case .grid(let grid): GridBlockView(model: model, grid: grid)
            case .picker(let kind): PickerBlockView(model: model, kind: kind)
            }
        }
    }

    private var removeControl: some View {
        Button("Remove this block", systemImage: "xmark") { model.remove(id) }
            .labelStyle(.iconOnly).buttonStyle(.ghost).foregroundStyle(.supporting)
            .focused($removeHasFocus)
            .opacity(isHovered || removeHasFocus ? 1 : 0)
            .help("Remove this block")
    }

    private var highlight: Color {
        switch shown.standing {
        case .added, .replacement: Tone.good.color.opacity(Self.highlightOpacity)
        case .live, .removed: .clear
        }
    }

    private var standingWords: String? {
        switch shown.standing {
        case .live: nil
        case .added: "New"
        case .replacement: "Replaces a block"
        case .removed: "Will be removed"
        }
    }

    static let highlightOpacity = 0.1
}

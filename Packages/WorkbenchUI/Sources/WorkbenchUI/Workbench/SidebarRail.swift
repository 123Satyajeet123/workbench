import AppKit
import SwiftUI

/// The sidebar folded to a column of faces: Mochi, then every machine in the order of the tree. A face shows its mood
/// and, on hover, its name. A click opens its page; a ⌘-click opens it in a new tab.
struct SidebarRail: View {
    static let width: CGFloat = 56

    @Binding var selection: SidebarSelection
    let openInNewTab: (SidebarSelection) -> Void
    @Environment(Crew.self) private var crew
    @Environment(WorkspaceModel.self) private var workspace
    @Environment(\.uiScale) private var scale

    var body: some View {
        ScrollView {
            VStack(spacing: Space.xs) {
                face(.mochi, look: .mochi, name: SidebarSelection.mochi.title, mood: crew.mochiMood)
                Divider().padding(.horizontal, Space.xs)
                ForEach(machines, id: \.machine.id) { helper in
                    face(
                        .machine(helper.machine.id), look: .of(helper.machine), name: helper.name, mood: helper.mood,
                        isPaused: helper.isPaused)
                }
            }
            .padding(Space.s)
        }
        .scrollClipDisabled()
        .frame(width: Self.width * scale)
        .background(.sidebarFill)
    }

    private var machines: [HelperModel] {
        let order = workspace.treeOrder
        func place(_ helper: HelperModel) -> Int { helper.machine.page.flatMap { order.firstIndex(of: $0) } ?? .max }
        return crew.crew.sorted { place($0) < place($1) }
    }

    private func face(
        _ page: SidebarSelection, look: Mascot.Look, name: String, mood: Mascot.Mood, isPaused: Bool = false
    ) -> some View {
        RailFace(look: look, name: name, mood: mood, isPaused: isPaused, isSelected: selection == page) {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                openInNewTab(page)
            } else {
                selection = page
            }
        }
        .contextMenu { Button("Open in new tab") { openInNewTab(page) } }
    }
}

private struct RailFace: View {
    private static let faceSide: CGFloat = 22
    private static let rowSide: CGFloat = 36

    let look: Mascot.Look
    let name: String
    let mood: Mascot.Mood
    let isPaused: Bool
    let isSelected: Bool
    let open: () -> Void
    @State private var isHovered = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: open) {
            Mascot(look: look, size: Self.faceSide, mood: mood).opacity(isPaused ? 0.5 : 1)
                .frame(maxWidth: .infinity).frame(height: Self.rowSide * scale).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(fill, in: .rect(cornerRadius: Radius.control))
        .pointerStyle(.link)
        .onHover { isHovered = $0 }
        .overlay {
            if isHovered {
                GeometryReader { row in
                    nameTag.frame(height: row.size.height).offset(x: row.size.width + Space.m)
                }
            }
        }
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var fill: Color { isSelected ? .selectedFill : isHovered ? .hoverFill : .clear }

    private var nameTag: some View {
        Text(name)
            .textStyle(.callout, weight: .medium)
            .foregroundStyle(.bodyText)
            .fixedSize()
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(.pageFill, in: .rect(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(.dividerLine))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

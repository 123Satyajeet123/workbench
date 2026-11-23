import SwiftUI

/// Where a page puts the Playbook of its step. The panel shows it when no fact is chosen. Only the page that is
/// showing owns the slot, so a page that closes cannot take down the one that opens.
@Observable
final class PlaybookSlot {
    private(set) var content: (() -> AnyView)?
    @ObservationIgnored private var owner: UUID?

    var hasContent: Bool { content != nil }

    func set(_ content: @escaping () -> AnyView, by owner: UUID) {
        self.content = content
        self.owner = owner
    }

    func clear(by owner: UUID) {
        guard self.owner == owner else { return }
        content = nil
        self.owner = nil
    }
}

private struct PlaybookModifier<Playbook: View>: ViewModifier {
    @ViewBuilder let playbook: () -> Playbook
    @Environment(PlaybookSlot.self) private var slot
    @State private var owner = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { slot.set({ AnyView(playbook()) }, by: owner) }
            .onDisappear { slot.clear(by: owner) }
    }
}

extension View {
    /// The Playbook of this page, shown in the window's right panel while no fact is chosen. The panel reads the
    /// models the content shows, so it stays current; a page with no Playbook sets none and the panel hides.
    func playbook<Playbook: View>(@ViewBuilder _ playbook: @escaping () -> Playbook) -> some View {
        modifier(PlaybookModifier(playbook: playbook))
    }
}

import SwiftUI

/// One short message at the bottom of the window.
struct Toast: Equatable, Identifiable {
    let id: Int
    let text: String
    let hasUndo: Bool
}

/// Holds the one toast a window shows. A new toast replaces the one before it. A toast goes after its lifetime, and
/// its undo then goes with it.
@Observable
final class ToastCenter {
    static let lifetime: Duration = .seconds(5)

    private(set) var current: Toast?
    @ObservationIgnored private var undoAction: (() -> Void)?
    @ObservationIgnored private var expiry: Task<Void, Never>?
    @ObservationIgnored private var shown = 0
    @ObservationIgnored private let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    func show(_ text: String, undo: (() -> Void)? = nil) {
        expiry?.cancel()
        shown += 1
        let toast = Toast(id: shown, text: text, hasUndo: undo != nil)
        current = toast
        undoAction = undo
        expiry = Task { [clock] in
            try? await clock.sleep(for: Self.lifetime)
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    /// Runs the undo of the toast on screen, once, and hides the toast. With no toast or no undo it does nothing.
    func undo() {
        guard let action = undoAction else { return }
        hide()
        action()
    }

    /// Hides the toast and drops its undo, for an undo done another way (⌘Z).
    func dismiss() { hide() }

    private func hide() {
        expiry?.cancel()
        current = nil
        undoAction = nil
    }
}

/// Gives its one child at most `limit` points of width, and takes only the width the child needs.
private struct CappedWidth: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews[0].sizeThatFits(capped(proposal))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }

    private func capped(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: min(proposal.width ?? limit, limit), height: proposal.height)
    }
}

struct ToastView: View {
    let toast: Toast
    let undo: () -> Void

    var body: some View {
        CappedWidth(limit: 480) {
            HStack(spacing: Space.s) {
                Text(toast.text).textStyle(.callout).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if toast.hasUndo {
                    Button(action: undo) {
                        HStack(spacing: Space.xs) {
                            Text("Undo").textStyle(.callout, weight: .semibold)
                            KeyHint("⌘Z")
                        }
                    }
                    .buttonStyle(.ghost)
                    .fixedSize()
                }
            }
            .padding(.leading, Space.m)
            .padding(.trailing, toast.hasUndo ? Space.xs : Space.m)
            .padding(.vertical, Space.xs)
        }
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.dividerLine))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }
}

private struct ToastHost: ViewModifier {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast = center.current {
                    ToastView(toast: toast, undo: center.undo)
                        .padding(.bottom, Space.l)
                        .padding(.horizontal, Space.l)
                        .transition(.opacity.combined(with: .offset(y: Space.s)))
                        .id(toast.id)
                }
            }
            .animation(Motion.snap(reduceMotion: reduceMotion), value: center.current)
            .onChange(of: center.current) { _, toast in
                if let toast { AccessibilityNotification.Announcement(toast.text).post() }
            }
    }
}

extension View {
    /// Draws the center's toast at the bottom centre of this view, above the content and without moving it.
    func toastHost(_ center: ToastCenter) -> some View {
        modifier(ToastHost(center: center))
    }
}

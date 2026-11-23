import Foundation

/// What one main window owns beside the session: the chosen fact, the page's Playbook, the toast, the proof reader and
/// how a fact is marked.
@MainActor
final class ShellState {
    let selection = FactSelection()
    let playbook = PlaybookSlot()
    let toast = ToastCenter()
    let proof: ProofModel
    let acting: ShellActing

    init(session: AppSession) {
        proof = ProofModel(today: session.today, crew: session.crew, store: session.store)
        acting = ShellActing(today: session.today, review: session.review, crew: session.crew)
    }
}

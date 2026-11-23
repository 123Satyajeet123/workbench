import SwiftUI
import WorkbenchCore

/// The one bar at the bottom of the page while a proposal waits: Mochi's line, each change the gate refused, and the
/// two buttons the person decides with.
struct ProposalBar: View {
    let note: String
    let refusals: [PageRefusal]
    let accept: () -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.s) {
                Mascot(look: .mochi, size: 18).accessibilityHidden(true)
                Text(note.isEmpty ? "I have a change for this page." : note).textStyle(.body)
                    .textSelection(.enabled)
            }
            ForEach(Array(refusals.enumerated()), id: \.offset) { _, refusal in
                Label(refusal.description, systemImage: "exclamationmark.circle").text(.meta)
            }
            HStack(spacing: Space.s) {
                Spacer()
                Button("Discard", action: discard).buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Button("Accept", action: accept).buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
        }
        .calloutBox(fillsWidth: true)
        .accessibilityElement(children: .contain)
    }
}

/// The box to ask the machine for a change. While the machine works, a quiet line says so and the box waits.
struct PageAskBox: View {
    let name: String
    let isAsking: Bool
    let send: (String) async -> Bool
    @State private var request = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            TextField("Ask \(name) to change this page…", text: $request)
                .textFieldStyle(.roundedBorder).disabled(isAsking).onSubmit(submit)
                .accessibilityLabel("Ask \(name) to change this page")
            if isAsking {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text("\(name) is working on it…").text(.meta)
                }
            }
        }
    }

    private func submit() {
        let words = request
        Task { if await send(words) { request = "" } }
    }
}

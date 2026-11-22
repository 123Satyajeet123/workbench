import SwiftUI
import WorkbenchCore

/// A question to the team's memory, answered only with citations the founder can open.
struct AskBox: View {
    @Environment(MemoryModel.self) private var memory
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                TextField("Ask your memory: what do we know about Acme?", text: $question)
                    .onSubmit(ask)
                Button(memory.asking ? "Asking…" : "Ask", action: ask)
                    .disabled(memory.asking || question.cleaned == nil)
            }
            if let problem = memory.problem { ProblemBanner(text: problem, dismiss: memory.clear) }
            if let answer = memory.answer {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(answer.text ?? "No answer in what you can see (\(answer.searched) entries searched).")
                        .textSelection(.enabled)
                    ForEach(answer.cited) { entry in
                        Text("“\(entry.quote)” · \(entry.source)").textStyle(.callout).foregroundStyle(.supporting)
                            .textSelection(.enabled)
                    }
                }
                .calloutBox()
            }
        }
    }

    private func ask() {
        let asked = question
        Task { await memory.ask(asked) }
    }
}

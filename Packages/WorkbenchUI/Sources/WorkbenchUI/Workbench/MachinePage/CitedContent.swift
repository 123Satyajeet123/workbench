import SwiftUI
import WorkbenchCore

/// Words a machine wrote, or a table it worked out, with one small chip for each thing it rests on. A chip of a fact
/// opens the fact as the app opens it everywhere; a chip of a paragraph or of the request is a plain label.
struct CitedContent<Content: View>: View {
    let model: MachinePageModel
    let cites: [PageCite]
    @ViewBuilder let content: Content
    @State private var inspected: Item?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            content
            HStack(spacing: Space.xs) {
                ForEach(Array(cites.enumerated()), id: \.offset) { _, cite in chip(for: cite) }
            }
            if let inspected { FactInspector(model: model, item: inspected) }
        }
    }

    @ViewBuilder private func chip(for cite: PageCite) -> some View {
        switch cite {
        case .fact(let id):
            if let item = model.facts.first(where: { $0.id == id }) {
                let label = FactHeadline(item: item, title: item[model.spec.title]).plain
                Button {
                    inspected = inspected?.id == id ? nil : item
                } label: {
                    Label(label, systemImage: "text.quote").lineLimit(1).pill()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open the fact: \(label)")
            } else {
                Text("A fact").pill()
            }
        case .note: Text("Your words").pill()
        case .request: Text("Your request").pill()
        }
    }
}

struct CitedTextView: View {
    let model: MachinePageModel
    let text: CitedText

    var body: some View {
        CitedContent(model: model, cites: text.cites) {
            Text(text.text).textStyle(.body).textSelection(.enabled)
        }
    }
}

/// One fact with its proof, drawn by the inspector the rest of the app uses.
struct FactInspector: View {
    let model: MachinePageModel
    let item: Item
    @Environment(Crew.self) private var crew
    @Environment(TodayModel.self) private var today
    @State private var proof: ProofModel?

    var body: some View {
        Group {
            if let proof {
                InspectorView(item: item, surface: .machinePage) { EmptyView() }.environment(proof).frame(
                    maxWidth: .infinity)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .onAppear { proof = ProofModel(today: today, crew: crew, store: model.store) }
    }
}

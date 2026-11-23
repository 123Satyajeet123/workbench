import SwiftUI

/// One row for each machine whose source needs a pick before it reads, such as the chats a chat machine reads. Each
/// row opens that source's own chooser.
struct SourceChoices: View {
    let machines: [HelperModel]
    @State private var choosing: HelperModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(machines, id: \.machine.id) { machine in
                ConnectRowView(
                    name: machine.name, detail: nil, status: machine.isReady ? .ready : .off,
                    actions: [action(for: machine)]
                ) {
                    Mascot(look: .of(machine.machine), size: 28)
                }
                if machine !== machines.last { Divider() }
            }
        }
        .padding(.horizontal, Space.m)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
        .sheet(isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } })) {
            if let choosing { SourceSheet(model: choosing) }
        }
    }

    private func action(for machine: HelperModel) -> ConnectAction {
        machine.isReady
            ? .init(title: "Change", isPrimary: false) { choosing = machine }
            : .init(title: "Choose \(machine.source.picks ?? "")", isPrimary: true) { choosing = machine }
    }
}

private struct SourceSheet: View {
    let model: HelperModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                Mascot(look: .of(model.machine), size: 36)
                Text("What \(model.name) reads").textStyle(.title2, weight: .bold)
            }
            .padding(Space.l)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    ProblemSlotBanner(slot: model.problems)
                    SourceChooser(model: model)
                }
                .padding([.horizontal, .bottom], Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
        }
        .zoomedWidth(520).frame(height: 560)
        .background(.pageFill)
        .onChange(of: model.isReady) { if model.isReady { dismiss() } }
        .task { model.problems.dismiss() }
    }
}

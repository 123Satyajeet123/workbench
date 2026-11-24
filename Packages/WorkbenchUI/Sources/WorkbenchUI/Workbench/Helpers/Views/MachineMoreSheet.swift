import SwiftUI

/// Everything about a machine that its document does not hold yet, in the screen it had before the document.
struct MachineMoreSheet: View {
    let model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @State private var isEditingBrief = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("More about \(model.name)").textStyle(.title2, weight: .bold)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Text(model.spec.brief).textStyle(.body).textSelection(.enabled)
                    Button("Edit brief…") { isEditingBrief = true }.buttonStyle(.ghost)
                    HelperContent(model: model)
                }
            }
        }
        .padding(Space.l)
        .frame(minWidth: 640, minHeight: 520)
        .sheet(isPresented: $isEditingBrief) { MachineSheet(edit: .brief(model)) { _ in } }
    }
}

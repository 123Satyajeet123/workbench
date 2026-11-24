import SwiftUI
import WorkbenchCore

/// One fact with its proof, drawn by the inspector the rest of the app uses, in a sheet over the page.
struct FactInspector: View {
    let model: MachinePageModel
    let item: Item
    @Environment(Crew.self) private var crew
    @Environment(TodayModel.self) private var today
    @Environment(\.dismiss) private var dismiss
    @State private var proof: ProofModel?

    var body: some View {
        VStack(spacing: 0) {
            if let proof {
                InspectorView(item: item, surface: .machinePage) { EmptyView() }.environment(proof)
            } else {
                Color.clear.frame(height: 1)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.primary).keyboardShortcut(.defaultAction)
            }
            .padding(Space.m)
        }
        .frame(minHeight: 320)
        .onAppear { proof = ProofModel(today: today, crew: crew, store: model.store) }
    }
}

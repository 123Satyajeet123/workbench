import SwiftUI
import WorkbenchCore

struct ViewPicker: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew

    var body: some View {
        let views = model.spec.views
        if views.count > 1 {
            ViewThatFits(in: .horizontal) {
                picker(views).pickerStyle(.segmented).fixedSize()
                picker(views).pickerStyle(.menu).fixedSize()
            }
        }
    }

    private func picker(_ views: [String: HelperSpec.View]) -> some View {
        Picker("View", selection: Binding(get: { current(in: views) }, set: { crew.show(model, as: $0) })) {
            ForEach(views.keys.sorted(), id: \.self) { Text($0.capitalized).tag($0) }
        }
        .labelsHidden()
    }

    private func current(in views: [String: HelperSpec.View]) -> String {
        views.first { $0.value == model.spec.view }?.key ?? "table"
    }
}

import SwiftUI

/// What a machine's document does not hold yet: its questions, its trial, its marks, what each source sends and how it
/// is shared.
struct MachineMoreSheet: View {
    let model: HelperModel
    @Environment(\.dismiss) private var dismiss
    @Environment(Crew.self) private var crew
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("More about \(model.name)").textStyle(.title2, weight: .bold)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if model.isChoosingSource { SourceChooser(model: model) }
                    if let update = crew.update(for: model) {
                        UpdateBanner(name: model.name, changes: update.changes) { crew.upgrade(model) }
                    }
                    if let question = model.question { HelperQuestion(model: model, item: question) }
                    if let notice = model.notice { NoticeRow(text: notice) { model.notice = nil } }
                    if model.isTrying { TrialCard(model: model) }
                    if let section = model.source.pageSection(for: model) { section }
                    if model.spec.criteria != nil, !model.isOutbound { AgreementSection(agreement: model.agreement) }
                    model.source.settingsView(for: model)
                    if !model.isTrying { ImproveRow(model: model) }
                    if catalog.folder != nil { ShareDayRow(model: model) }
                }
            }
        }
        .padding(Space.l)
        .frame(minWidth: 640, minHeight: 520)
    }
}

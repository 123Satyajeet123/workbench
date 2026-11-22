import SwiftUI
import WorkbenchCore

struct HelperContent: View {
    let model: HelperModel
    @Environment(ActionsModel.self) private var actions
    @Environment(Crew.self) private var crew

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            ProblemSlotBanner(slot: model.problems)
            ActionNotice()
            if model.isPaused { PausedNote(model: model) }
            if let update = crew.update(for: model) {
                UpdateBanner(name: model.name, changes: update.changes) { crew.upgrade(model) }
            }
            if model.isReady {
                readyContent
            } else {
                SourceChooser(model: model)
            }
        }
        .sheet(item: Binding(get: { actions.draft }, set: { actions.draft = $0 })) { DraftSheet(draft: $0) }
        .task(id: model.scope) { await loadMembers() }
        .onAppear(perform: model.reload)
    }

    @ViewBuilder private var readyContent: some View {
        ReadBar(model: model)
        if let question = model.question { HelperQuestion(model: model, item: question) }
        if let notice = model.notice { NoticeRow(text: notice) { model.notice = nil } }
        if model.isTrying { TrialCard(model: model) }
        items
        if model.spec.criteria != nil {
            CriteriaSection(helper: model)
            AgreementSection(agreement: model.agreement)
        }
        MachineSettings(model: model)
    }

    @ViewBuilder private var items: some View {
        switch model.spec.view {
        case .board(let field, let expected): ItemBoard(model: model, field: field, expected: expected)
        case .timeline: ForEach(model.items) { ItemRow(model: model, item: $0, showsSpan: true) }
        case .table: ItemTable(model: model)
        case .grouped(let field): ItemGroups(model: model, field: field)
        case .checklist(let field): ItemChecklist(model: model, field: field)
        }
    }

    private func loadMembers() async {
        guard let source = model.source as? WhatsAppSource else { return }
        do {
            try await source.showMembers()
        } catch {
            model.problems.report("read the group members", error)
        }
    }
}

import SwiftUI
import WorkbenchCore

/// Everything a helper shows for one day: its setup until it is ready, then the read button, the nudge and the
/// items in the view its spec names.
struct HelperContent: View {
    let model: HelperModel
    @Environment(TeamCatalogModel.self) private var catalog
    @Environment(ActionsModel.self) private var actions
    @Environment(Crew.self) private var crew

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let problem = model.problem { ProblemBanner(text: problem, dismiss: model.dismissProblem) }
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
        ReadControls(model: model)
        if let question = model.question { HelperQuestion(model: model, item: question) }
        if let notice = model.notice { NoticeRow(text: notice) { model.notice = nil } }
        if model.trial != nil || model.trialPhase == .reading {
            TrialCard(model: model)
        } else {
            ImproveRow(model: model)
        }
        if model.spec.nudge != nil { NudgeRow(model: model) }
        WatchRow(model: model)
        if catalog.folder != nil { ShareDayRow(model: model) }
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
            model.attempt("read the group members") { throw error }
        }
    }
}

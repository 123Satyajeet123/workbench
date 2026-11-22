import Foundation
import Observation
import WorkbenchCore

@Observable
final class CriteriaModel {
    private(set) var draft: Criteria
    var form: RuleDraft?

    @ObservationIgnored private let helper: HelperModel
    static let previewDays = 90

    init(helper: HelperModel) {
        self.helper = helper
        draft = helper.spec.criteria ?? Criteria()
    }

    var saved: Criteria { helper.spec.criteria ?? Criteria() }
    var isChanged: Bool { draft != saved }
    var blocker: String? { draft.problem }

    var preview: CriteriaPreview {
        CriteriaPreview(
            items: helper.items(since: Self.previewDays), title: helper.spec.title, current: saved, edited: draft)
    }

    func add() { form = RuleDraft() }
    func edit(_ rule: Rule) { form = RuleDraft(rule) }
    func cancelForm() { form = nil }

    func commitForm() {
        guard let form, let rule = form.rule() else { return }
        draft = form.editing.map { draft.replacing($0, with: rule) } ?? draft.adding(rule)
        self.form = nil
    }

    func remove(_ rule: Rule) { draft = draft.removing(rule.id) }

    func setRole(_ role: Rule.Role, of rule: Rule) {
        var edited = rule
        edited.role = role
        draft = draft.replacing(rule.id, with: edited)
    }

    func setHotAt(_ points: Int) { draft.hotAt = points }

    func discard() {
        draft = saved
        form = nil
    }

    func save(into crew: Crew) {
        guard blocker == nil else { return }
        crew.setCriteria(helper, draft)
        draft = helper.spec.criteria ?? draft
    }
}

import Foundation
import Observation
import WorkbenchCore

/// The criteria editor's state: the founder's unsaved edits to a machine's criteria, and what they would do to the
/// deals already read. Nothing reaches the machine until `save`; saving is a new prompt version.
@Observable
final class CriteriaModel {
    private(set) var draft: Criteria
    var form: RuleDraft?

    @ObservationIgnored private let helper: HelperModel
    /// How far back the preview looks for deals already read.
    static let previewDays = 90

    init(helper: HelperModel) {
        self.helper = helper
        draft = helper.spec.criteria ?? Criteria()
    }

    var saved: Criteria { helper.spec.criteria ?? Criteria() }
    var isChanged: Bool { draft != saved }
    /// What stops the draft from being saved, in words; nil when it can be.
    var blocker: String? { draft.problem }

    /// The effect of the unsaved edits on the deals already read, worked out in code with no model call.
    var preview: CriteriaPreview {
        CriteriaPreview(
            items: helper.items(since: Self.previewDays), title: helper.spec.title, current: saved, edited: draft)
    }

    func add() { form = RuleDraft() }
    func edit(_ rule: Rule) { form = RuleDraft(rule) }
    func cancelForm() { form = nil }

    /// Puts the form's rule in the draft: a new rule at the end, or an edit in place.
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

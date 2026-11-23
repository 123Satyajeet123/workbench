import Foundation
import Observation
import WorkbenchCore

/// The criteria editor's state: the founder's unsaved edits to criteria, and what they would do to the deals already
/// read. Nothing is kept until `save`; saving a machine's criteria is a new prompt version.
@Observable
final class CriteriaModel {
    private(set) var draft: Criteria
    private(set) var saved: Criteria
    var form: RuleDraft?

    @ObservationIgnored private let title: String
    @ObservationIgnored private let items: (Int) -> [Item]
    static let previewDays = 90

    init(saved: Criteria, title: String, items: @escaping (Int) -> [Item] = { _ in [] }) {
        self.saved = saved
        self.title = title
        self.items = items
        draft = saved
    }

    convenience init(helper: HelperModel) {
        self.init(
            saved: helper.spec.criteria ?? Criteria(), title: helper.spec.title, items: helper.items(since:))
    }

    var isChanged: Bool { draft != saved }
    var blocker: String? { draft.problem }

    /// The effect of the unsaved edits on the deals already read, worked out in code with no model call.
    var preview: CriteriaPreview {
        CriteriaPreview(
            items: items(Self.previewDays), title: title, current: saved, edited: draft)
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

    /// Keeps the draft as the saved criteria and hands it to `persist`. A draft with a problem is kept by nobody.
    func save(_ persist: (Criteria) -> Void) {
        guard blocker == nil else { return }
        saved = draft
        persist(draft)
    }
}

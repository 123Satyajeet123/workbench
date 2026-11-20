import CaptureService
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// A thesis with a number rule, a must, a deal-breaker, a plus and a minus, and deals read under it.
enum VCFixture {
    static let employees = Rule(
        id: "r_emp", role: .plus,
        test: .number(NumberTest(measure: "employee count", unit: "people", comparison: .atLeast, low: 20)))
    static let mrr = Rule(
        id: "r_mrr", role: .must,
        test: .number(NumberTest(measure: "monthly revenue", unit: "USD", comparison: .atLeast, low: 10_000)))
    static let india = Rule(
        id: "r_in", role: .must, test: .text(TextTest(says: "The startup is based in India", wants: true)))
    static let gambling = Rule(
        id: "r_gamble", role: .dealBreaker, test: .text(TextTest(says: "Gambling, betting or gaming", wants: false)))
    static let team = Rule(
        id: "r_team", role: .plus, test: .text(TextTest(says: "The founders worked in the sector before", wants: true)))
    static let thesis = Criteria(rules: [india, mrr, gambling, employees, team])

    /// What the model's readings of one deal look like in an item: an answer and its quote for each rule given. A
    /// rule of words also gets a reason.
    static func reading(_ answers: [(rule: Rule, answer: String, quote: String)]) -> [String: String] {
        var fields = ["company": "Acme"]
        for (rule, answer, quote) in answers {
            fields[rule.id] = answer
            fields[rule.quoteKey] = quote
            if case .text = rule.test { fields[rule.reasonKey] = "Because the page says so." }
        }
        return fields
    }

    static let hot = reading([
        (india, "yes", "Bengaluru-based"), (mrr, "42000", "$42k MRR"), (gambling, "no", "payroll software"),
        (employees, "38", "a team of 38"), (team, "yes", "ex-Razorpay founders"),
    ])
    static let missingNumber = reading([
        (india, "yes", "Bengaluru-based"), (mrr, "", ""), (gambling, "no", "payroll software"),
        (employees, "12", "12 people"), (team, "yes", "ex-Razorpay founders"),
    ])
    static let breaker = reading([
        (india, "yes", "Bengaluru-based"), (mrr, "80000", "$80k MRR"), (gambling, "yes", "fantasy sports app"),
        (employees, "60", "60 people"), (team, "yes", "ex-Dream11 founders"),
    ])
}

@Suite struct RuleDraftTests {
    @Test func aDraftMakesTheRuleItWasMadeFromAndKeepsItsId() throws {
        for rule in Criteria(rules: [VCFixture.employees, VCFixture.india, VCFixture.gambling]).rules {
            #expect(RuleDraft(rule).rule() == rule)
        }
    }

    @Test func aDraftWithoutSoundFieldsMakesNoRule() {
        var draft = RuleDraft()
        #expect(draft.rule() == nil, "no words")
        draft.says = "B2B"
        #expect(draft.rule() != nil)
        draft.kind = .number
        #expect(draft.rule() == nil, "no measure and no number")
        draft.measure = "employees"
        draft.low = "twenty"
        #expect(draft.rule() == nil, "not a number")
        draft.low = "20"
        #expect(draft.rule() != nil)
        draft.comparison = .between
        #expect(draft.rule() == nil, "a range needs its top")
        draft.high = "50"
        #expect(
            draft.rule()?.test
                == .number(.init(measure: "employees", unit: "", comparison: .between, low: 20, high: 50)))
    }

    @Test func aDontWantDraftMakesAnAvoidRule() {
        var draft = RuleDraft()
        draft.kind = .avoid
        draft.says = "gambling"
        #expect(draft.rule()?.test == .text(TextTest(says: "gambling", wants: false)))
    }
}

@Suite struct CriteriaEditorTests {
    private func setUp() throws -> (Store, Crew, HelperModel) {
        let store = try scratchStore()
        let crew = Crew(
            store: store, capture: try CaptureService(store: store), founder: { "Aditya" }, notifier: FakeNotifier())
        let id = try #require(crew.create(spec: .dealIntake, template: "vc.deals", name: "Deal intake"))
        return (store, crew, try #require(crew.helper(id: id)))
    }

    /// Stores one deal as a reading of the machine would, under a real run.
    private func read(_ fields: [String: String], by intake: HelperModel, in store: Store) async throws {
        let (_, run) = try await RecordedModel(ScriptedModel("{}"), store: store)
            .generate(
                [String: JSONValue].self, schema: .object([]), task: intake.spec.task, instructions: "i", input: "x",
                holding: [.mail])
        let day = intake.day
        let item = Item(
            task: intake.spec.task, day: day, scope: intake.scope, source: .mail, citeFirst: 1, citeLast: 1,
            start: day.start, end: day.start, fields: fields, quote: "q", run: run)
        let policy = CapturePolicy(switches: [.mail: true], allowList: [.mail: ["Deals"]])
        try store.saveReading(
            HelperReader.Result(items: [item], dropped: 0, run: nil), of: intake.spec, day: day, scope: intake.scope,
            grant: try #require(policy.authorize(CaptureRequest(kind: .mail, label: "Deals"), at: .now).grant),
            replacing: false)
    }

    @Test func savingNewCriteriaIsANewPromptVersionAndAnUnsavedEditChangesNothing() throws {
        let (_, crew, intake) = try setUp()
        let editor = CriteriaModel(helper: intake)
        let before = HelperReader(
            spec: intake.spec, model: RecordedModel(ScriptedModel("{}"), store: try scratchStore()))
        editor.add()
        editor.form?.says = "Sells to banks"
        editor.commitForm()
        #expect(editor.isChanged && intake.spec.criteria == editor.saved, "nothing is saved before Save")
        editor.save(into: crew)
        let after = HelperReader(
            spec: intake.spec, model: RecordedModel(ScriptedModel("{}"), store: try scratchStore()))
        #expect(!editor.isChanged && intake.spec.criteria?.rules.count == 3)
        #expect(after.instructions != before.instructions && after.instructions.contains("Sells to banks"))
    }

    @Test func discardAndAnInvalidDraftChangeNothing() throws {
        let (_, crew, intake) = try setUp()
        let editor = CriteriaModel(helper: intake)
        editor.remove(try #require(editor.draft.rules.first))
        editor.discard()
        #expect(editor.draft == editor.saved)
        editor.add()
        editor.form?.kind = .number
        editor.form?.measure = "x"
        editor.form?.low = "5"
        editor.form?.comparison = .between
        editor.form?.high = "2"
        editor.commitForm()
        #expect(editor.form != nil && !editor.isChanged, "a range with its top below its bottom is not added")
        editor.form?.high = "9"
        editor.commitForm()
        #expect(editor.isChanged && editor.blocker == nil)
        editor.save(into: crew)
        #expect(intake.spec.criteria?.rules.count == 3)
    }

    @Test func thePreviewRescoresDealsAlreadyReadWithNoModelCall() async throws {
        let (store, crew, intake) = try setUp()
        var thesis = VCFixture.thesis
        thesis.hotAt = 1
        crew.setCriteria(intake, thesis)
        try await read(VCFixture.hot, by: intake, in: store)
        try await read(VCFixture.missingNumber, by: intake, in: store)
        let editor = CriteriaModel(helper: intake)
        #expect(editor.preview.rows.map(\.was) == [.hot, .warm])
        var strict = try #require(editor.draft.rule("r_mrr"))
        strict.test = .number(.init(measure: "monthly revenue", unit: "USD", comparison: .atLeast, low: 50_000))
        editor.edit(strict)
        editor.commitForm()
        let rows = editor.preview.rows
        #expect(rows.map(\.now) == [.cold, .warm], "a limit of 50k fails the 42k deal; the unknown number never fails")
        #expect(rows[0].unread == 0 && editor.preview.changed.count == 1)
        #expect(intake.spec.criteria == thesis, "unsaved")
    }
}

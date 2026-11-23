import SwiftUI
import WorkbenchCore

/// One card for each question of the chosen template. The editor of a card follows the kind of the question, never
/// the name of the template.
struct SetupStep: View {
    static let saveTitle = "Save answer"

    @Environment(OnboardingModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(model.questions) { question in
                Card(
                    title: "\(question.machineNames.formatted(.list(type: .and))): \(question.kind.title)",
                    symbol: question.kind.symbol
                ) {
                    if let explanation = question.kind.explanation {
                        Text(explanation).textStyle(.callout).foregroundStyle(.supporting)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    editor(for: question)
                    AnswerStatus(question: question)
                }
            }
        }
    }

    @ViewBuilder private func editor(for question: SetupQuestion) -> some View {
        let spec = model.templateSpec(of: question)
        let answer = model.answers[question]
        let save = { (answer: SetupAnswer) in model.answer(question, with: answer) }
        switch question.kind {
        case .criteria:
            CriteriaQuestion(initial: answer?.criteria ?? spec.criteria ?? Criteria(), title: spec.title, save: save)
                .id(answer != nil)
        case .feeds:
            FeedsQuestion(initial: answer?.feeds ?? spec.feeds ?? [], save: save).id(answer != nil)
        case .claimTypes:
            ClaimTypesQuestion(initial: answer?.claimTypes ?? spec.claimTypes ?? [], save: save).id(answer != nil)
        }
    }
}

private struct AnswerStatus: View {
    let question: SetupQuestion
    @Environment(OnboardingModel.self) private var model

    var body: some View {
        if model.answers[question] != nil {
            HStack {
                Label("Your answer is kept. Workbench saves it when setup ends.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.supporting)
                Button("Use the template’s values") { model.useDefaults(for: question) }
                    .buttonStyle(.ghost).foregroundStyle(.linkText)
            }
            .textStyle(.callout)
        } else {
            Text("No answer. The template’s values stay.").textStyle(.callout).foregroundStyle(.supporting)
        }
    }
}

private struct CriteriaQuestion: View {
    let save: (SetupAnswer) -> Void
    @State private var model: CriteriaModel

    init(initial: Criteria, title: String, save: @escaping (SetupAnswer) -> Void) {
        self.save = save
        _model = State(initialValue: CriteriaModel(saved: initial, title: title))
    }

    var body: some View {
        CriteriaBody(
            model: model, save: { model.save { save(.criteria($0)) } }, showsPreview: false,
            saveTitle: SetupStep.saveTitle)
    }
}

private struct FeedsQuestion: View {
    let save: (SetupAnswer) -> Void
    let initial: [NewsFeed]
    @State private var draft: FeedsDraft

    init(initial: [NewsFeed], save: @escaping (SetupAnswer) -> Void) {
        self.save = save
        self.initial = initial
        _draft = State(initialValue: FeedsDraft(initial))
    }

    var body: some View {
        ListEditor(
            problem: draft.problem, isChanged: draft.feeds != initial, add: { draft.add() },
            save: { draft.feeds.map { save(.feeds($0)) } }, discard: { draft = FeedsDraft(initial) },
            rows: {
                ForEach($draft.rows) { $row in
                    HStack(spacing: Space.s) {
                        TextField("Name", text: $row.name, prompt: Text("Name")).frame(maxWidth: 140)
                        TextField("Address", text: $row.address, prompt: Text("Web address"))
                        Toggle("Trusted", isOn: $row.trusted).toggleStyle(.checkbox)
                        RemoveButton { draft.remove(row) }
                    }
                }
            })
    }
}

private struct ClaimTypesQuestion: View {
    let save: (SetupAnswer) -> Void
    let initial: [ClaimType]
    @State private var draft: ClaimTypesDraft

    init(initial: [ClaimType], save: @escaping (SetupAnswer) -> Void) {
        self.save = save
        self.initial = initial
        _draft = State(initialValue: ClaimTypesDraft(initial))
    }

    var body: some View {
        ListEditor(
            problem: draft.problem, isChanged: draft.types != initial, add: { draft.add() },
            save: { draft.types.map { save(.claimTypes($0)) } }, discard: { draft = ClaimTypesDraft(initial) },
            rows: {
                ForEach($draft.rows) { $row in
                    HStack(spacing: Space.s) {
                        TextField("Label", text: $row.label, prompt: Text("Label")).frame(maxWidth: 140)
                        TextField(
                            "What counts as proof", text: $row.proof, prompt: Text("What counts as proof"),
                            axis: .vertical
                        )
                        .lineLimit(1...4)
                        RemoveButton { draft.remove(row) }
                    }
                }
            })
    }
}

private struct ListEditor<Rows: View>: View {
    let problem: String?
    let isChanged: Bool
    let add: () -> Void
    let save: () -> Void
    let discard: () -> Void
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            rows.textFieldStyle(.roundedBorder)
            Button("Add a row", systemImage: "plus", action: add).buttonStyle(.ghost)
            if let problem { Text(problem).textStyle(.callout).foregroundStyle(Tone.bad.color) }
            HStack {
                Button(SetupStep.saveTitle, action: save).disabled(!isChanged || problem != nil)
                Button("Discard changes", action: discard).disabled(!isChanged)
            }
        }
    }
}

private struct RemoveButton: View {
    let remove: () -> Void

    var body: some View {
        Button("Remove", systemImage: "minus.circle", action: remove).labelStyle(.iconOnly).buttonStyle(.ghost)
    }
}

extension SetupQuestion.Kind {
    var title: String {
        switch self {
        case .criteria: "your criteria"
        case .feeds: "news feeds"
        case .claimTypes: "claim types"
        }
    }

    var symbol: String {
        switch self {
        case .criteria: "slider.horizontal.3"
        case .feeds: "newspaper"
        case .claimTypes: "checkmark.seal"
        }
    }

    var explanation: String? {
        switch self {
        case .criteria: nil
        case .feeds: "The machine reads only these feeds. A bad signal from a trusted feed goes to Today."
        case .claimTypes: "What a claim can be about, and what counts as proof of it."
        }
    }
}

extension SetupAnswer {
    var criteria: Criteria? { if case .criteria(let value) = self { value } else { nil } }
    var feeds: [NewsFeed]? { if case .feeds(let value) = self { value } else { nil } }
    var claimTypes: [ClaimType]? { if case .claimTypes(let value) = self { value } else { nil } }
}

import SwiftUI
import WorkbenchCore

/// The page of a machine as one document: the job, then the person's paragraphs and the machine's blocks in one
/// order, then the machine's proposal and the box to ask it for a change. The job is edited where it stands.
struct MachinePageView: View {
    let model: MachinePageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            JobHeader(model: model)
            ProblemSlotBanner(slot: model.problems)
            ForEach(model.slots, id: \.self) { PageSlotView(model: model, slot: $0) }
            if let proposal = model.proposal {
                ProposalBar(
                    note: proposal.note, refusals: model.refusals,
                    accept: { Task { await model.accept() } }, discard: model.discard)
            }
            PageAskBox(name: model.name, isAsking: model.isAsking) { await model.ask($0) }
        }
        .toastHost(model.toast)
        .keepsSaved(model.editor, reconcile: model.refresh)
    }
}

/// What the machine is for, in one sentence in the person's words, edited where it stands; what it reads; what it is
/// doing now; and the brief the machine itself is told, which opens in the same editor as the sidebar's.
private struct JobHeader: View {
    let model: MachinePageModel
    @Environment(Crew.self) private var crew
    @State private var isEditingBrief = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            InPlaceText(
                text: model.job ?? "", prompt: "Say what \(model.name) is for.", isEditing: isEditingJob,
                commit: { crew.setJob(model.helper, to: $0) })
            Text("Reads: \(model.reads)").text(.meta)
            if let now = model.nowLine() { Text(now).text(.meta) }
            Fold {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(model.spec.brief).textStyle(.body).textSelection(.enabled)
                    Button("Edit brief…") { isEditingBrief = true }.buttonStyle(.ghost)
                }
                .padding(.top, Space.xs)
            } label: {
                Text("How it works").text(.meta)
            }
        }
        .sheet(isPresented: $isEditingBrief) { MachineSheet(edit: .brief(model.helper)) { _ in } }
    }

    private var isEditingJob: Binding<Bool> {
        Binding(get: { model.editing == .job }, set: { model.setEditing(.job, $0) })
    }
}

private struct PageSlotView: View {
    let model: MachinePageModel
    let slot: PageSlot

    var body: some View {
        switch slot {
        case .run(let index): RunEditor(model: model, index: index)
        case .machine(let id):
            if let shown = model.shown.blocks[id] { MachineBlockView(model: model, id: id, shown: shown) }
        }
    }
}

/// The paragraphs of the person between two machine blocks, as a text to write in.
private struct RunEditor: View {
    static let placeholder = "Write here."

    let model: MachinePageModel
    let index: Int
    @Environment(\.uiScale) private var scale

    var body: some View {
        NoteTextEditor(model: model.run(index), minimumHeight: 24 * scale)
            .overlay(alignment: .topLeading) {
                if index == model.runs.lastRun, model.run(index).text.isEmpty {
                    Text(Self.placeholder).textStyle(.body).foregroundStyle(.supporting).allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Your words")
    }
}

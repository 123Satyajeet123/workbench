import SwiftUI
import WorkbenchCore

/// The page of a machine as one document: the job, then the person's paragraphs and the machine's blocks in one
/// order, then the machine's proposal and the box to ask it for a change.
struct MachinePageView: View {
    let model: MachinePageModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            JobHeader(job: model.job, brief: model.spec.brief, reads: model.reads)
            ProblemSlotBanner(slot: model.problems)
            if model.hasNothingYet {
                Text("Nothing here yet. Ask \(model.name) for a view of its facts.").text(.meta)
            }
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

/// What the machine is for, in one sentence in the person's words, and what it reads. The brief is what the machine
/// itself is told: it is one click away, and it changes in the settings.
private struct JobHeader: View {
    let job: String?
    let brief: String
    let reads: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Label {
                    Text("The job").text(.sectionTitle)
                } icon: {
                    Image(systemName: "gearshape").foregroundStyle(.iconTint)
                }
                if let job { Text(job).textStyle(.body).textSelection(.enabled) }
                Text("Reads: \(reads)").text(.meta)
            }
            .accessibilityElement(children: .combine)
            Fold {
                Text(brief).textStyle(.body).textSelection(.enabled).padding(.top, Space.xs)
            } label: {
                Text("How it works").text(.meta)
            }
        }
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

    private var isWholePage: Bool { model.runs.lastRun == 0 }

    var body: some View {
        NoteTextEditor(model: model.run(index), minimumHeight: (isWholePage ? 96 : 24) * scale)
            .overlay(alignment: .topLeading) {
                if isWholePage, model.editor.text.isEmpty {
                    Text(Self.placeholder).textStyle(.body).foregroundStyle(.supporting).allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Your words")
    }
}

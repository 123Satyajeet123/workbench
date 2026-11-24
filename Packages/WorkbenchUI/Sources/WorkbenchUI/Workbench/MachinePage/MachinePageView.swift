import AppKit
import SwiftUI
import WorkbenchCore

/// The page of a machine as one document: the job, then the editor that holds the person's paragraphs and the
/// machine's blocks in one order, then the machine's proposal and the box to ask it for a change. The job is edited
/// where it stands.
struct MachinePageView: View {
    let model: MachinePageModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            JobHeader(model: model)
            ProblemSlotBanner(slot: model.problems)
            if let editor = model.editor { DocumentView(host: editor.host) }
            if let proposal = model.proposal {
                ProposalBar(
                    note: proposal.note, refusals: model.refusals,
                    accept: { Task { await model.accept() } }, discard: model.discard)
            }
            PageAskBox(name: model.name, isAsking: model.isAsking) { await model.ask($0) }
        }
        .toastHost(model.toast)
        .keepsSaved({ model.editor }, refresh: model.refresh)
        .onChange(of: look, initial: true) { _, look in
            model.openEditor(appearance: look.appearance, reduceMotion: look.reduceMotion, scale: look.scale)
            model.editor?.setAppearance(look.appearance, reduceMotion: look.reduceMotion, scale: look.scale)
        }
        .sheet(item: inspectedBinding) { FactInspector(model: model, item: $0) }
        .sheet(isPresented: isChoosing) {
            if let kind = model.choosing { PickerSheet(kind: kind, helper: model.helper) }
        }
    }

    private struct Look: Equatable {
        let appearance: EditorEnvironment.Appearance
        let reduceMotion: Bool
        let scale: Double
    }

    private var look: Look {
        Look(appearance: colorScheme == .dark ? .dark : .light, reduceMotion: reduceMotion, scale: scale)
    }

    private var inspectedBinding: Binding<Item?> { Binding(get: { model.inspected }, set: { model.inspected = $0 }) }
    private var isChoosing: Binding<Bool> {
        Binding(get: { model.choosing != nil }, set: { if !$0 { model.choosing = nil } })
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
                commit: { crew.setJob(model.helper, to: $0) }
            )
            .textStyle(.documentBody)
            Text("Reads: \(model.reads)").text(.meta)
            MachineStatusView(
                isReading: model.helper.phase == .reading, shows: .journal(isOpen: false), read: model.status)
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

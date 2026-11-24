import AppKit
import SwiftUI
import WorkbenchCore

/// The page of a machine as one document: the editor that holds the title, the job, the machine's account of itself,
/// the person's paragraphs, the machine's blocks and how the machine works, in one order. The sheets are what a
/// phrase of the document opens.
struct MachinePageView: View {
    @Bindable var model: MachinePageModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            if let editor = model.editor { DocumentView(host: editor.host) }
        }
        .toastHost(model.toast)
        .keepsSaved({ model.editor }, refresh: model.refresh)
        .onChange(of: look, initial: true) { _, look in
            model.openEditor(appearance: look.appearance, reduceMotion: look.reduceMotion, scale: look.scale)
            model.editor?.setAppearance(look.appearance, reduceMotion: look.reduceMotion, scale: look.scale)
        }
        .task(id: model.helper.phase) { await model.keepStatusFresh() }
        .sheet(isPresented: $model.isShowingMore) { MachineMoreSheet(model: model.helper) }
        .sheet(isPresented: $model.isEditingBrief) { MachineSheet(edit: .brief(model.helper)) { _ in } }
        .sheet(isPresented: $model.isEditingCriteria) { CriteriaSheet(helper: model.helper) }
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

import SwiftUI
import WorkbenchCore

/// A page no machine owns, as a document the person writes in: the same editor as a machine's page, with no machine blocks.
struct PlainPageDocument: View {
    let page: WorkObjectID
    @Environment(Crew.self) private var crew
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.uiScale) private var scale
    @State private var editor: PageEditorController?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let problem { Text(problem).text(.meta) }
            if let editor { DocumentView(host: editor.host) }
        }
        .keepsSaved({ editor }, refresh: refresh)
        .onChange(of: look, initial: true) { _, look in
            open(look)
            editor?.setAppearance(look.appearance, reduceMotion: look.reduceMotion, scale: look.scale)
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

    private func refresh() {
        do { try editor?.refresh() } catch { problem = "Could not read this page: \(error.localizedDescription)" }
    }

    private func open(_ look: Look) {
        guard editor == nil, case .success(let owner) = crew.owner else { return }
        do {
            let controller = try PageEditorController(
                store: crew.store, page: page, owner: owner, host: EditorHost(), appearance: look.appearance,
                reduceMotion: look.reduceMotion, scale: look.scale,
                views: {
                    MachineViewBuilder(
                        facts: [], titleOf: { _ in "" }, lens: FactsLens(spec: .pages, now: Date()), pickerNote: { _ in nil })
                })
            controller.onOpen = { target in
                if case .link(let address) = target { EditorHost.openLink(address) }
            }
            controller.start()
            editor = controller
        } catch {
            problem = "Could not open this page: \(error.localizedDescription)"
        }
    }
}

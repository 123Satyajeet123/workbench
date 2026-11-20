import SwiftUI

/// Everything that sets up a machine, folded at the bottom of its page: what reading sends, ways to improve it, its
/// schedule and sharing. Closed until the founder opens it, so the page starts with content.
struct MachineSettings: View {
    let model: HelperModel
    @Environment(TeamCatalogModel.self) private var catalog
    @State private var isOpen = false

    var body: some View {
        DisclosureGroup("Settings", isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: Space.l) {
                ReadNote(model: model)
                if !model.isTrying { ImproveRow(model: model) }
                if model.spec.nudge != nil { NudgeRow(model: model) }
                WatchRow(model: model)
                if catalog.folder != nil { ShareDayRow(model: model) }
            }
            .padding(.top, Space.m)
        }
        .textStyle(.headline)
    }
}

extension HelperModel {
    /// A new version is on trial or being read for one.
    var isTrying: Bool { trial != nil || trialPhase == .reading }
}

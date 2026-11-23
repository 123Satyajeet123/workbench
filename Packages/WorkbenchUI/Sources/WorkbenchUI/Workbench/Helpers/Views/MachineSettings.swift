import SwiftUI

/// Everything that sets up a machine, folded at the bottom of its page: what reading sends, ways to improve it, its
/// schedule and sharing. Closed until the founder opens it, so the page starts with content.
struct MachineSettings: View {
    let model: HelperModel
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        Fold("Settings") {
            VStack(alignment: .leading, spacing: Space.l) {
                ReadNote(model: model)
                if let whatsApp = model.source as? WhatsAppSource { ChosenChats(model: model, source: whatsApp) }
                if !model.isTrying { ImproveRow(model: model) }
                if model.spec.nudge != nil { NudgeRow(model: model) }
                if model.isOutbound { WeeklySearchRow(model: model) } else { WatchRow(model: model) }
                if catalog.folder != nil { ShareDayRow(model: model) }
            }
            .padding(.top, Space.m)
        }
        .textStyle(.headline)
    }
}

extension HelperModel {
    var isTrying: Bool { trial != nil || trialPhase == .reading }
}

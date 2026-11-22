import SwiftUI

struct MachineSettings: View {
    let model: HelperModel
    @State private var isOpen = false

    var body: some View {
        DisclosureGroup("Settings", isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: Space.l) {
                ReadNote(model: model)
                if !model.isTrying { ImproveRow(model: model) }
                if model.spec.nudge != nil { NudgeRow(model: model) }
                WatchRow(model: model)
            }
            .padding(.top, Space.m)
        }
        .textStyle(.headline)
    }
}

extension HelperModel {
    var isTrying: Bool { trial != nil || trialPhase == .reading }
}

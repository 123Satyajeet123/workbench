import SwiftUI
import WorkbenchCore

struct WelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.m) {
                    Mascot(look: .mochi, size: 36)
                    VStack(alignment: .leading, spacing: Space.xs / 2) {
                        Text(SidebarSelection.mochi.title).textStyle(.headline)
                        Text("Writes your day and spots work you repeat.").foregroundStyle(.supporting)
                    }
                }
                Text("Machines keep one kind of work from the sources you choose. You pick them next.")
                    .foregroundStyle(.supporting)
            }
            Label(OnboardingStep.dataLine, systemImage: "lock")
                .textStyle(.callout)
                .foregroundStyle(.supporting)
                .fixedSize(horizontal: false, vertical: true)
                .calloutBox(fillsWidth: true)
        }
    }
}

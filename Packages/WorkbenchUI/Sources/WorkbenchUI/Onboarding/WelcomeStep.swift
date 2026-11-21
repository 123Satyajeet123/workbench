import SwiftUI

struct WelcomeStep: View {
    private struct Member {
        let look: Mascot.Look
        let name: String
        let line: String
    }

    private static let crew = [
        Member(look: .mochi, name: SidebarSelection.mochi.title, line: "Writes your day and spots work you repeat."),
        Member(
            look: .pip, name: MachineTemplate.team.name,
            line: "Keeps your team's plans, blockers and promises from WhatsApp."),
        Member(look: .echo, name: SidebarSelection.calls.title, line: "Records the calls you choose."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(Self.crew, id: \.name) { member in
                    HStack(spacing: Space.m) {
                        Mascot(look: member.look, size: 36)
                        VStack(alignment: .leading, spacing: Space.xs / 2) {
                            Text(member.name).textStyle(.headline)
                            Text(member.line).foregroundStyle(.supporting)
                        }
                    }
                }
            }
            Label(OnboardingStep.dataLine, systemImage: "lock")
                .textStyle(.callout)
                .foregroundStyle(.supporting)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
        }
    }
}

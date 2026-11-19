import SwiftUI

struct OnboardingStep: View {
    let screen: OnboardingScreen

    static let dataLine =
        "Your data stays on this Mac. Only what you ask Workbench to read goes to the model you choose, and each call is logged."

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(screen.title).textStyle(.largeTitle, weight: .bold).fixedSize(horizontal: false, vertical: true)
            Text(screen.lead).textStyle(.title3).fixedSize(horizontal: false, vertical: true)
            switch screen {
            case .welcome: Text(Self.dataLine).textStyle(.title3, weight: .semibold)
            case .you: YouStep()
            case .team: TeamEditor()
            case .sources: Form { SourceToggles() }.formStyle(.grouped).scrollDisabled(true)
            case .done: LoginItemToggle().toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

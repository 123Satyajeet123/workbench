import SwiftUI

struct OnboardingStep: View {
    let screen: OnboardingScreen

    static let dataLine =
        "Your data stays on this Mac. Only what you ask Workbench to read goes to the model you choose, and each call is logged."

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(screen.title).font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
            Text(screen.lead).font(.title3).fixedSize(horizontal: false, vertical: true)
            switch screen {
            case .welcome: Text(Self.dataLine).font(.title3.weight(.semibold))
            case .you: YouStep()
            case .sources: Form { SourceToggles() }.formStyle(.grouped).scrollDisabled(true)
            case .done: LoginItemToggle().toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

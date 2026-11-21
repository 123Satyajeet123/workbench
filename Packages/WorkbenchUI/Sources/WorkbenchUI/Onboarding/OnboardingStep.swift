import AppKit
import SwiftUI

struct OnboardingStep: View {
    let screen: OnboardingScreen
    let facts: ConnectFacts

    static let dataLine =
        "Your data stays on this Mac. Only what you ask Workbench to read goes to the model you choose, and each call is logged."

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.m) {
                if screen == .welcome {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                } else if let look = screen.look {
                    Mascot(look: look, size: 52)
                }
                Text(title).textStyle(.largeTitle, weight: .bold).fixedSize(horizontal: false, vertical: true)
                Text(screen.lead).textStyle(.title3).foregroundStyle(.supporting)
                    .fixedSize(horizontal: false, vertical: true)
            }
            switch screen {
            case .welcome: WelcomeStep()
            case .you: YouStep()
            case .team: TeamEditor()
            case .connect: ConnectList(facts: facts)
            case .done:
                ConnectList(facts: facts, isChecklist: true)
                LoginItemToggle().toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var title: String {
        screen == .done && !facts.isSet ? "Almost there" : screen.title
    }
}

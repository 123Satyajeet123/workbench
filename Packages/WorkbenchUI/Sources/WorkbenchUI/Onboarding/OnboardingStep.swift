import AppKit
import SwiftUI

struct OnboardingStep: View {
    let screen: OnboardingScreen
    let facts: ConnectFacts
    @Environment(OnboardingModel.self) private var model

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
            case .team: TeamStep()
            case .connect:
                ConnectList(facts: facts, needs: model.needs)
                if model.needs.isEmpty {
                    Text("Your team’s machines read no source yet. You can turn one on later in Settings.")
                        .textStyle(.callout).foregroundStyle(.supporting)
                }
            case .setup: SetupStep()
            case .watchlist: WatchlistStep()
            case .firstLook: FirstLookStep()
            case .done:
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(model.summary(connected: connected).lines, id: \.self) { Text($0).textStyle(.callout) }
                }
                ConnectList(facts: facts, needs: model.needs, isChecklist: true)
                LoginItemToggle().toggleStyle(.switch)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var connected: [String] {
        facts.sourceRows.filter { facts.status(of: $0).isDone }.compactMap(\.sourceName)
    }

    private var title: String {
        screen == .done && !facts.isSet ? "Almost there" : screen.title
    }
}

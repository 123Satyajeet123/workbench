import SwiftUI

struct OnboardingView: View {
    static let size = CGSize(width: 640, height: 600)
    static let stepWidth = size.width - 2 * Space.page
    static let stepHeight: CGFloat = 440

    @Environment(OnboardingModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingProgress(index: model.index, count: model.screens.count)
                .padding(.bottom, Space.l)
            OnboardingStep(screen: model.screen)
                .id(model.screen)
                .transition(.opacity)
                .frame(width: Self.stepWidth, height: Self.stepHeight, alignment: .topLeading)
            Spacer(minLength: 0)
            if let problem = model.problem {
                ProblemBanner(text: problem).padding(.bottom, Space.s)
            }
            footer
        }
        .padding(Space.page)
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(.easeInOut(duration: 0.25), value: model.index)
        .navigationTitle("Set up Workbench")
    }

    private var footer: some View {
        HStack {
            if !model.isFirst {
                Button("Back", action: model.back)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Button(continueTitle, action: model.next)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinue)
        }
        .controlSize(.large)
    }

    private var continueTitle: String {
        switch model.screen {
        case .welcome: "Get started"
        case .done: "Open Workbench"
        case .you, .sources: "Continue"
        }
    }
}

private struct OnboardingProgress: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<count, id: \.self) { step in
                Circle()
                    .fill(step <= index ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

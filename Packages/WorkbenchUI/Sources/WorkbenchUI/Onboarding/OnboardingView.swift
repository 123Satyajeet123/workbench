import AppKit
import SwiftUI

struct OnboardingView: View {
    static let size = CGSize(width: 640, height: 600)

    @Environment(OnboardingModel.self) private var model
    @Environment(CaptureSettings.self) private var capture
    @Environment(TodayModel.self) private var today
    @Environment(Crew.self) private var crew
    @Environment(ModelSettings.self) private var models
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var access = MacAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                Text("Set up Workbench").textStyle(.callout).foregroundStyle(.supporting)
                OnboardingProgress(index: model.index, count: model.screens.count)
            }
            .padding([.horizontal, .top], Space.page)
            .padding(.bottom, Space.l)
            ScrollView {
                OnboardingStep(
                    screen: model.screen,
                    facts: ConnectFacts(access: access, capture: capture, today: today, pip: crew.team)
                )
                .padding(.horizontal, Space.page)
                .padding(.bottom, Space.l)
            }
            .scrollBounceBehavior(.basedOnSize)
            .id(model.screen)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: Space.m)), removal: .opacity))
            VStack(spacing: Space.s) {
                if let problem = model.problem { ProblemBanner(text: problem) }
                footer
            }
            .padding([.horizontal, .bottom], Space.page)
            .padding(.top, Space.m)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(Motion.settle(reduceMotion: reduceMotion), value: model.index)
        .environment(access)
        .onAppear(perform: recheck)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recheck()
        }
    }

    private func recheck() {
        access.recheck(reader: models.choice.kind)
        if capture.isOn(.calendar) { Task { await today.refreshMeetings() } }
    }

    private var footer: some View {
        HStack {
            if !model.isFirst {
                Button("Back", action: model.back)
                    .buttonStyle(.ghost)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Button(continueTitle, action: model.next)
                .buttonStyle(.primary)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canContinue)
        }
        .controlSize(.large)
    }

    private var continueTitle: String {
        switch model.screen {
        case .welcome: "Get started"
        case .done: "Open Workbench"
        case .you, .team, .connect: "Continue"
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
                    .fill(step <= index ? Color.accentFill : Color.bodyText.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

import SwiftUI
import WorkbenchCore

/// One line about a change the app made by itself.
struct NoticeRow: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Label(text, systemImage: "arrow.uturn.backward.circle").foregroundStyle(Tone.attention.color)
            Button("Dismiss", action: dismiss).buttonStyle(.borderless)
        }
    }
}

/// A paused machine reads and nudges nothing until the founder resumes it.
struct PausedNote: View {
    let model: HelperModel
    @Environment(Crew.self) private var crew

    var body: some View {
        HStack(spacing: Space.s) {
            Label("\(model.name) is paused. It reads and nudges nothing.", systemImage: "pause.circle")
            Button("Resume") { crew.setPaused(model, false) }
        }
        .foregroundStyle(Tone.attention.color)
    }
}

/// The result of the last act, or why it could not happen.
struct ActionNotice: View {
    @Environment(ActionsModel.self) private var actions

    var body: some View {
        if let problem = actions.problem {
            ProblemBanner(text: problem, dismiss: actions.dismiss)
        } else if actions.remindersBlocked {
            HStack {
                Text("Reminders is off for Workbench. Turn it on in System Settings, then try again.")
                Button("Open Settings", action: AppleReminders.openSettings)
                Button("Dismiss", action: actions.dismiss)
            }
        } else if let notice = actions.notice {
            HStack {
                Label(notice, systemImage: "checkmark.circle").foregroundStyle(Tone.good.color)
                Button("Dismiss", action: actions.dismiss).buttonStyle(.borderless)
            }
        }
    }
}

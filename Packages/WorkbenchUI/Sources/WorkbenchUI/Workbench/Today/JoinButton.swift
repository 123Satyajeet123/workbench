import SwiftUI
import WorkbenchCore

struct JoinButton: View {
    static let soon: TimeInterval = 10 * 60

    let meeting: Meeting
    var now = Date.now

    var body: some View {
        if let url = meeting.joinURL {
            let label = Label("Join", systemImage: "video")
            Group {
                if Self.isDue(meeting, at: now) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        label
                    }.buttonStyle(.primary)
                } else {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        label
                    }.buttonStyle(.ghost)
                }
            }
            .help(meeting.joinService.map { "Join on \($0)" } ?? "Join: \(url.host() ?? url.absoluteString)")
            .accessibilityLabel(meeting.joinService.map { "Join on \($0)" } ?? "Join the meeting")
        }
    }

    static func isDue(_ meeting: Meeting, at now: Date) -> Bool {
        now >= meeting.start.addingTimeInterval(-soon) && now < meeting.end
    }
}

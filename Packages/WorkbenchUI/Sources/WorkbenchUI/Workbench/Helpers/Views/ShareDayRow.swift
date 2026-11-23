import SwiftUI
import WorkbenchCore

/// Shares the shown day's items with the team: only the items, their quotes and the founder's marks, and only to
/// teammates who can already read the source.
struct ShareDayRow: View {
    let model: HelperModel
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                if catalog.isShared(day: model) {
                    Label("Shared with your team", systemImage: "person.2.fill").foregroundStyle(Tone.good.color)
                    Button("Update") { Task { await catalog.share(day: model) } }
                    Button("Stop sharing") { catalog.unshare(day: model) }
                } else {
                    Button("Share this day with the team") { Task { await catalog.share(day: model) } }
                        .disabled(model.items.isEmpty)
                        .help(
                            "Shares the items, their quotes and your marks; never the other messages or windows. Only to teammates who can already read the source."
                        )
                }
            }
            if let refusal = catalog.refusal, refusal.task == model.spec.task {
                RefusalCard(model: model, refusal: refusal)
            }
        }
    }
}

struct RefusalCard: View {
    let model: HelperModel
    let refusal: TeamCatalogModel.Refusal
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Not shared", systemImage: "hand.raised").textStyle(.headline)
            if refusal.group.isEmpty {
                Text(
                    "These items come from your screen, which only you can see. Window titles can name other people's mail and chats, so they stay on your Mac."
                )
            } else {
                Text(
                    "Workbench shares a group's items only with teammates who are in that group. Say who each one is in it, then choose Share again."
                )
                ForEach(refusal.missing) { person in
                    Menu("Who is \(person.name) in the group?") {
                        ForEach(refusal.group, id: \.jid) { member in
                            Button(member.name) { Task { await catalog.link(person, to: member, for: model) } }
                        }
                    }
                    .fixedSize()
                }
                Text("A teammate who is not in the group cannot receive its items.").textStyle(.callout)
                    .foregroundStyle(.supporting)
            }
            Button("Dismiss", action: catalog.dismissRefusal)
        }
        .calloutBox()
    }
}

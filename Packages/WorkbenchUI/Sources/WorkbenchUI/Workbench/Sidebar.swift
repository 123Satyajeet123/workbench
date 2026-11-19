import SwiftUI

struct Sidebar: View {
    @Binding var selection: SidebarSelection
    @Environment(IdentityModel.self) private var identity
    @Environment(Crew.self) private var crew

    var body: some View {
        List(selection: Binding<SidebarSelection?>(get: { selection }, set: { if let new = $0 { selection = new } })) {
            HelperRow(page: .day, faceSize: 34, mood: mood(.day)).tag(SidebarSelection.day)
            Section("Crew") {
                ForEach(SidebarSelection.crew) { HelperRow(page: $0, faceSize: 26, mood: mood($0)).tag($0) }
            }
            Section("Meter") {
                Label(SidebarSelection.runs.title, systemImage: "gauge.with.dots.needle.33percent")
                    .tag(SidebarSelection.runs)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        .safeAreaInset(edge: .bottom) {
            SettingsLink {
                HStack(spacing: Space.s) {
                    Monogram(name: identity.identity.hasName ? identity.identity.name : "You")
                    Text(identity.identity.hasName ? identity.identity.name : "You").lineLimit(1)
                    Spacer()
                    Image(systemName: "gearshape").foregroundStyle(.supporting)
                }
                .padding(Space.m)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
    }
}

extension Sidebar {
    /// Mochi asks when any helper asks; a helper page shows its own helper.
    fileprivate func mood(_ page: SidebarSelection) -> Mascot.Mood {
        guard page == .day else { return crew.helper(for: page)?.mood ?? .calm }
        let moods = [crew.timeline.mood, crew.team.mood]
        return [.working, .trouble, .asking].first(where: moods.contains) ?? .calm
    }
}

private struct HelperRow: View {
    let page: SidebarSelection
    let faceSize: CGFloat
    let mood: Mascot.Mood

    var body: some View {
        HStack(spacing: Space.s) {
            if let look = page.look { Mascot(look: look, size: faceSize, mood: mood) }
            VStack(alignment: .leading, spacing: 0) {
                Text(page.title).fontWeight(.medium)
                Text(page.role).font(.caption).foregroundStyle(.supporting)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

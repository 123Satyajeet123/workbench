import SwiftUI

enum QuickOpen {
    struct Entry: Identifiable, Equatable {
        enum Kind: String {
            case page = "Page"
            case machine = "Machine"
            case person = "Person"
            case project = "Project"
            case setting = "Setting"
        }

        var title: String
        var kind: Kind
        var page: SidebarSelection
        var settingsSection: SettingsSection?
        var words = ""
        var id: String { "\(kind.rawValue):\(title)" }
    }

    static func entries(
        pages: [SidebarSelection], machines: [(id: Int64, name: String)], people: [String], projects: [String],
        settings: [SettingsItem] = []
    ) -> [Entry] {
        pages.map { Entry(title: $0.title, kind: .page, page: $0) }
            + machines.map { Entry(title: $0.name, kind: .machine, page: .machine($0.id)) }
            + people.map { Entry(title: $0, kind: .person, page: .people) }
            + projects.map { Entry(title: $0, kind: .project, page: .projects) }
            + settings.map {
                Entry(title: $0.title, kind: .setting, page: .settings, settingsSection: $0.section, words: $0.words)
            }
    }

    static func search(_ entries: [Entry], for query: String) -> [Entry] {
        let byTitle = FuzzySearch.filter(entries, by: query, name: \.title)
        let titled = Set(byTitle.map(\.id))
        let byWord = FuzzySearch.filter(entries.filter { !titled.contains($0.id) && !$0.words.isEmpty }, by: query) {
            $0.words
        }
        return byTitle + (query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : byWord)
    }
}

struct QuickOpenPanel: View {
    let entries: [QuickOpen.Entry]
    let open: (QuickOpen.Entry, _ inNewTab: Bool) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var chosen = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        let shown = Array(QuickOpen.search(entries, for: query).prefix(12))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.supporting)
                TextField("Search pages, machines, people and projects", text: $query)
                    .textFieldStyle(.plain).textStyle(.title3).focused($isFocused)
                    .onChange(of: query) { chosen = 0 }
                    .onKeyPress(.downArrow) { move(1, in: shown) }
                    .onKeyPress(.upArrow) { move(-1, in: shown) }
                    .onKeyPress(.escape) {
                        close()
                        return .handled
                    }
                    .onKeyPress(.return, phases: .down) { press in
                        guard shown.indices.contains(chosen) else { return .ignored }
                        open(shown[chosen], press.modifiers.contains(.command))
                        return .handled
                    }
            }
            .padding(Space.m)
            Divider()
            if shown.isEmpty {
                Text("Nothing matches “\(query)”.").foregroundStyle(.supporting).padding(Space.m)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, entry in
                HStack {
                    Text(entry.title).lineLimit(1)
                    Spacer()
                    Text(entry.kind.rawValue).textStyle(.callout).foregroundStyle(.supporting)
                }
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .background(index == chosen ? Color.selectedFill : .clear, in: .rect(cornerRadius: Radius.control))
                .contentShape(.rect)
                .pointerStyle(.link)
                .onTapGesture { open(entry, NSApp.currentEvent?.modifierFlags.contains(.command) == true) }
                .onHover { if $0 { chosen = index } }
                .accessibilityAddTraits(.isButton)
            }
            Text("Return opens here · ⌘Return opens in a new tab · Esc closes")
                .textStyle(.callout).foregroundStyle(.supporting).padding(Space.m)
        }
        .padding(Space.xs)
        .frame(width: 520)
        .background(.pageFill, in: .rect(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(.dividerLine))
        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
        .onAppear { isFocused = true }
    }

    private func move(_ step: Int, in shown: [QuickOpen.Entry]) -> KeyPress.Result {
        guard !shown.isEmpty else { return .ignored }
        chosen = (chosen + step + shown.count) % shown.count
        return .handled
    }
}

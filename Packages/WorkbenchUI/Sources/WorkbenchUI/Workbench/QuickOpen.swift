import SwiftUI

enum QuickOpen {
    struct Entry: Identifiable, Equatable {
        enum Kind: String {
            case page = "Page"
            case person = "Person"
            case project = "Project"
            case setting = "Setting"
            case action = "Action"
        }

        /// What choosing the entry does: open a page (a settings entry also names its section), or switch the data
        /// the app has open.
        enum Target: Equatable {
            case page(SidebarSelection, section: SettingsSection? = nil)
            case switchProfile(Profile)
        }

        var title: String
        var kind: Kind
        var target: Target
        var words = ""
        /// What the entry is, shown beside it, when the kind says too little: a work object's noun.
        var noun: String?
        var id: String { "\(kind.rawValue):\(title):\(target)" }
    }

    /// `objects` are the work objects of the tree, each with the noun shown beside it and the page it opens.
    /// `switchTo` is the data the app can switch to now, if any; its entry is listed last.
    static func entries(
        pages: [SidebarSelection], objects: [(name: String, noun: String, page: SidebarSelection)], people: [String],
        projects: [String], settings: [SettingsItem] = [], switchTo: Profile? = nil
    ) -> [Entry] {
        pages.map { Entry(title: $0.title, kind: .page, target: .page($0)) }
            + objects.map { Entry(title: $0.name, kind: .page, target: .page($0.page), noun: $0.noun) }
            + people.map { Entry(title: $0, kind: .person, target: .page(.people)) }
            + projects.map { Entry(title: $0, kind: .project, target: .page(.projects)) }
            + settings.map {
                Entry(
                    title: $0.title, kind: .setting, target: .page(.settings, section: $0.section), words: $0.words)
            }
            + (switchTo.map {
                [
                    Entry(
                        title: ProfileSwitch.title(to: $0), kind: .action, target: .switchProfile($0),
                        words: "demo synthetic sample example")
                ]
            } ?? [])
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
                TextField("Search pages, folders, machines, people and projects", text: $query)
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
                    Text(entry.noun ?? entry.kind.rawValue).textStyle(.callout).foregroundStyle(.supporting)
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
        .background(.pageFill)
        .defaultFocus($isFocused, true)
    }

    private func move(_ step: Int, in shown: [QuickOpen.Entry]) -> KeyPress.Result {
        guard !shown.isEmpty else { return .ignored }
        chosen = (chosen + step + shown.count) % shown.count
        return .handled
    }
}

import SwiftUI
import WorkbenchCore

/// The sidebar's entries, top to bottom: the one place to reorder, add or drop one.
enum SidebarLayout {
    enum Entry: Equatable {
        /// A tool page, beside its symbol.
        case page(SidebarSelection, symbol: String)
        /// A fixed helper's page, with its face and role.
        case helper(SidebarSelection)
        /// One row for each machine of the crew.
        case machines
    }

    struct Section: Equatable {
        var title: String?
        var entries: [Entry]
    }

    static let sections = [
        Section(entries: [
            .page(.day, symbol: "sun.max"), .page(.people, symbol: "person.2"),
            .page(.projects, symbol: "square.stack.3d.up"),
        ]),
        Section(entries: [.helper(.calls), .page(.deals, symbol: "rectangle.3.group")]),
        Section(
            title: "Crew",
            entries: [
                .helper(.mochi), .page(.crew, symbol: "rectangle.grid.2x2"), .machines,
                .page(.review, symbol: "checkmark.circle"), .page(.catalog, symbol: "person.crop.rectangle.stack"),
            ]),
    ]
}

/// The sidebar, drawn after Notion's: grey symbols, compact rows whose titles all start at one place, small grey
/// section labels, and a soft grey fill under the pointer and on the open page. Its top row sits in the window's
/// title bar, beside the window's buttons, and holds the toggle that hides it.
struct Sidebar: View {
    @Binding var selection: SidebarSelection
    /// The height of the window's title bar.
    let titleBar: CGFloat
    /// Where the toggle starts: just right of the window's buttons.
    let toggleLeading: CGFloat
    let hide: () -> Void
    @Environment(IdentityModel.self) private var identity
    @Environment(Crew.self) private var crew
    @Environment(ReviewModel.self) private var review
    @Environment(TodayModel.self) private var today
    @Environment(TeamCatalogModel.self) private var catalog
    @State private var editing: MachineEdit?
    @State private var deleting: HelperModel?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SidebarLayout.sections.indices, id: \.self) { index in
                        section(SidebarLayout.sections[index])
                    }
                }
                .padding(.horizontal, Space.s)
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)
            }
            settingsRow
        }
        .padding(.top, titleBar)
        .background(.sidebarFill)
        // An overlay, not the first row: the list's scroll view reaches up into the title bar's safe area, which is
        // taller than this row once the window has a toolbar, and as a row the toggle sat under it and took no clicks.
        .overlay(alignment: .top) { topRow }
        .sheet(item: $editing) { edit in
            MachineSheet(edit: edit) { id in if let id { selection = .machine(id) } }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { helper in
            Button("Delete \(helper.name)", role: .destructive) {
                if selection == .machine(helper.machine.id) { selection = .day }
                crew.delete(helper)
            }
        } message: { helper in
            Text(
                "Its \(helper.spec.itemsNoun), your marks on them and its settings are deleted. Its runs stay in Settings › Advanced."
            )
        }
    }

    /// The strip in the title bar: it moves the window and holds the toggle, just right of the window's buttons. Its
    /// fill hides rows scrolled up beneath it.
    private var topRow: some View {
        HStack {
            SidebarToggle(isShown: true, toggle: hide).padding(.leading, toggleLeading)
            Spacer()
        }
        .frame(height: titleBar)
        .background(.sidebarFill)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
    }

    /// A section with a title stands apart, as Notion's Favorites and Shared do; one without runs on from the one above.
    private func section(_ section: SidebarLayout.Section) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = section.title { label(title, addsMachine: section.entries.contains(.machines)) }
            ForEach(section.entries.indices, id: \.self) { index in entry(section.entries[index]) }
        }
        .padding(.top, section.title == nil ? 1 : Space.l)
    }

    private func label(_ title: String, addsMachine: Bool) -> some View {
        HStack {
            Text(title).textStyle(.callout, weight: .medium).foregroundStyle(.sidebarLabel)
            Spacer()
            if addsMachine {
                Button("Add a machine", systemImage: "plus") { editing = .new }
                    .labelStyle(.iconOnly).buttonStyle(.ghost).foregroundStyle(.sidebarIcon)
                    .help("Add a machine")
            }
        }
        .padding(.leading, Space.s)
        .padding(.bottom, Space.xs)
    }

    /// Every row is one line, as in Notion. A helper's role shows under the pointer and to VoiceOver; a paused machine
    /// says so where a count would be.
    @ViewBuilder private func entry(_ entry: SidebarLayout.Entry) -> some View {
        switch entry {
        case .page(let page, let symbol):
            let count = count(of: page)
            row(page) {
                SidebarRow(
                    title: page.title, icon: .symbol(symbol), detail: count > 0 ? count.formatted() : nil,
                    isSelected: selection == page)
            }
        case .helper(let page):
            row(page, role: page.role) {
                SidebarRow(
                    title: page.title,
                    icon: page.look.map { .face($0, page == .mochi ? mochiMood : .calm) } ?? .symbol("circle"),
                    isSelected: selection == page)
            }
        case .machines:
            ForEach(crew.crew, id: \.machine.id) { helper in
                let page = SidebarSelection.machine(helper.machine.id)
                row(page, role: MachineTemplate.of(helper.machine)?.role) {
                    SidebarRow(
                        title: helper.name, icon: .face(.of(helper.machine), helper.mood),
                        detail: helper.isPaused ? "Paused" : nil, isSelected: selection == page,
                        dimsIcon: helper.isPaused)
                }
                .contextMenu { menu(for: helper) }
            }
        }
    }

    private func row(_ page: SidebarSelection, role: String? = nil, @ViewBuilder label: () -> some View) -> some View {
        Button {
            selection = page
        } label: {
            label()
        }
        .buttonStyle(SidebarRowStyle(isSelected: selection == page))
        .help(role ?? "")
        .accessibilityHint(role ?? "")
        .accessibilityAddTraits(selection == page ? .isSelected : [])
    }

    private func count(of page: SidebarSelection) -> Int {
        switch page {
        case .day: today.needs.count
        case .review: review.items.count
        case .catalog: catalog.teammates.count + catalog.teammatesDays.count
        default: 0
        }
    }

    @ViewBuilder private func menu(for helper: HelperModel) -> some View {
        Button("Rename…") { editing = .rename(helper) }
        Button("Edit brief…") { editing = .brief(helper) }
        Button(helper.isPaused ? "Resume" : "Pause") { crew.setPaused(helper, !helper.isPaused) }
        if catalog.isShared(helper) {
            Button("Stop sharing") { catalog.unshare(helper) }
        } else {
            Button("Share with team") { catalog.share(helper) }.disabled(catalog.folder == nil)
        }
        if catalog.isShared(helper, in: .everyone) {
            Button("Unpublish") { catalog.unshare(helper, from: .everyone) }
        } else {
            Button("Publish to the public catalog") { catalog.share(helper, to: .everyone) }
                .disabled(catalog.publicFolder == nil)
        }
        Divider()
        Button("Delete…", role: .destructive) { deleting = helper }
    }

    private var settingsRow: some View {
        SettingsLink {
            HStack(spacing: Space.s) {
                Monogram(name: identity.identity.hasName ? identity.identity.name : "You")
                Text(identity.identity.hasName ? identity.identity.name : "You").lineLimit(1)
                    .sidebarTitle(isSelected: false)
                Spacer()
                Image(systemName: "gearshape").foregroundStyle(.sidebarIcon)
            }
            .padding(Space.s)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowStyle(isSelected: false))
        .padding(Space.s)
        .help("Settings (⌘,)")
    }

    /// Mochi shows the most urgent mood of the crew.
    private var mochiMood: Mascot.Mood {
        let moods = crew.machines.map(\.mood)
        return [.working, .trouble, .asking].first(where: moods.contains) ?? .calm
    }
}

/// Shows and hides the sidebar: a plain grey symbol with a soft fill under the pointer and no glass, as in Notion.
struct SidebarToggle: View {
    let isShown: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "sidebar.left").textStyle(.title3).foregroundStyle(.sidebarIcon)
        }
        .buttonStyle(.ghost)
        .keyboardShortcut("s", modifiers: [.control, .command])
        .help(isShown ? "Hide the sidebar (⌃⌘S)" : "Show the sidebar (⌃⌘S)")
        .accessibilityLabel(isShown ? "Hide the sidebar" : "Show the sidebar")
    }
}

/// One sidebar row. Every icon, a symbol or a helper's face, fills the same square, so every title starts at the same
/// place whatever the icon. One line, as in Notion; a page with things waiting shows how many at the trailing edge.
private struct SidebarRow: View {
    enum Icon {
        case symbol(String)
        case face(Mascot.Look, Mascot.Mood)
    }

    /// The icon square, the symbol's point size and the row's least height, at actual size; zoom scales them. Sizes
    /// and weights are Notion's, measured from its sidebar.
    private static let iconSide: CGFloat = 20
    private static let symbolSize: CGFloat = 15
    private static let height: CGFloat = 30

    let title: String
    let icon: Icon
    /// Grey words at the trailing edge: how many wait, or that a machine is paused.
    var detail: String?
    let isSelected: Bool
    /// A paused machine's face is dimmed; its words keep their colour, so they stay readable.
    var dimsIcon = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        let side = Self.iconSide * scale
        HStack(spacing: Space.s) {
            Group {
                switch icon {
                case .symbol(let name):
                    // Drawn at a point size, not scaled to fit, so its strokes keep the medium weight.
                    Image(systemName: name).font(.system(size: Self.symbolSize * scale, weight: .medium))
                        .foregroundStyle(isSelected ? Color.sidebarSelectedText : .sidebarIcon)
                case .face(let look, let mood): Mascot(look: look, size: side, mood: mood)
                }
            }
            .frame(width: side, height: side)
            .opacity(dimsIcon ? 0.5 : 1)
            Text(title).lineLimit(1).sidebarTitle(isSelected: isSelected)
            Spacer(minLength: Space.xs)
            if let detail { Text(detail).textStyle(.callout, digits: true).foregroundStyle(.sidebarLabel) }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
        .frame(minHeight: Self.height * scale)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A sidebar row's fill: the selected page and a pressed row in the selected grey, a row under the pointer in the
/// hover grey.
private struct SidebarRowStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SidebarRowBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct SidebarRowBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: .rect(cornerRadius: Radius.control))
            .onHover { isHovered = $0 }
    }

    private var fill: Color {
        if isSelected || configuration.isPressed { return .selectedFill }
        return isHovered ? .hoverFill : .clear
    }
}
/// What the machine sheet is for: a new machine, a new name, or a new brief.
enum MachineEdit: Identifiable {
    case new
    case rename(HelperModel)
    case brief(HelperModel)

    var id: String {
        switch self {
        case .new: "new"
        case .rename(let helper): "rename-\(helper.machine.id)"
        case .brief(let helper): "brief-\(helper.machine.id)"
        }
    }
}

private struct MachineSheet: View {
    let edit: MachineEdit
    let done: (Int64?) -> Void
    @Environment(Crew.self) private var crew
    @Environment(\.dismiss) private var dismiss
    @State private var template = MachineTemplate.team
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(title).textStyle(.title2, weight: .bold)
            switch edit {
            case .new:
                Picker("Kind", selection: $template) {
                    ForEach(MachineTemplate.all) { Text($0.role).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(template.detail).foregroundStyle(.supporting)
                if lacksFollowable { Text(Crew.nothingToFollow).foregroundStyle(Tone.bad.color) }
                TextField("Name", text: $text, prompt: Text(template.name)).textFieldStyle(.roundedBorder)
            case .rename:
                TextField("Name", text: $text).textFieldStyle(.roundedBorder)
                Text("A new name keeps its items, marks and trust.").foregroundStyle(.supporting)
            case .brief(let helper):
                TextEditor(text: $text).textStyle(.body).frame(minHeight: 180).border(.quaternary)
                Button("Try on past days first") {
                    let brief = text
                    Task { await helper.startTrial(brief: brief) }
                    dismiss()
                }
                .help(
                    "Reads up to \(HelperImprovement.trialDays) recent days with the new brief beside the current one. Nothing changes until you switch."
                )
                Text(
                    "A new brief is a new version. Its marks and trust start again; the old version's stay in Settings › Advanced."
                )
                .foregroundStyle(.supporting)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action: save) { Text(saveTitle) }.buttonStyle(.primary).keyboardShortcut(
                    .defaultAction
                ).disabled(lacksFollowable)
            }
        }
        .padding(Space.l)
        .frame(width: 480)
        .onAppear(perform: fill)
    }

    /// A new machine that follows another has nothing to follow until a machine with a lifecycle (Pip) exists.
    private var lacksFollowable: Bool {
        guard case .new = edit else { return false }
        return template.spec.needsFollowed && crew.followable == nil
    }

    private var title: String {
        switch edit {
        case .new: "Add a machine"
        case .rename(let helper): "Rename \(helper.name)"
        case .brief(let helper): "\(helper.name)'s brief"
        }
    }

    private var saveTitle: String {
        switch edit {
        case .new: "Add"
        case .rename: "Rename"
        case .brief: "Save version"
        }
    }

    private func fill() {
        switch edit {
        case .new: text = ""
        case .rename(let helper): text = helper.name
        case .brief(let helper): text = helper.spec.brief
        }
    }

    private func save() {
        switch edit {
        case .new: done(crew.create(from: template, name: text))
        case .rename(let helper):
            crew.rename(helper, to: text)
            done(nil)
        case .brief(let helper):
            crew.edit(helper, brief: text)
            done(nil)
        }
        dismiss()
    }
}

extension View {
    /// A sidebar title as Notion sets it: 14 pt medium in the sidebar's warm grey, brighter on the open page.
    fileprivate func sidebarTitle(isSelected: Bool) -> some View {
        modifier(SidebarTitle(isSelected: isSelected))
    }
}

private struct SidebarTitle: ViewModifier {
    private static let size: CGFloat = 14

    let isSelected: Bool
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View {
        content.font(.system(size: Self.size * scale, weight: .medium))
            .foregroundStyle(isSelected ? Color.sidebarSelectedText : .sidebarText)
    }
}

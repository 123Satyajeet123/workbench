import SwiftUI
import WorkbenchCore

enum SidebarLayout {
    enum Entry: Equatable {
        case page(SidebarSelection, symbol: String)
        case helper(SidebarSelection)
        case machines
    }

    struct Section: Equatable {
        var title: String?
        var entries: [Entry]
    }

    static let sections = [
        Section(entries: [
            .page(.day, symbol: "sun.max"), .page(.people, symbol: "person.2"),
            .page(.projects, symbol: "square.stack.3d.up"), .helper(.calls),
        ]),
        Section(
            title: "Crew",
            entries: [
                .helper(.mochi), .page(.crew, symbol: "rectangle.grid.2x2"), .machines,
                .page(.review, symbol: "checkmark.circle"),
            ]),
    ]

    static func lists(_ page: SidebarSelection) -> Bool {
        if case .machine = page { return true }
        return sections.flatMap(\.entries).contains { entry in
            switch entry {
            case .page(let listed, _), .helper(let listed): listed == page
            case .machines: false
            }
        }
    }
}

struct Sidebar: View {
    @Binding var selection: SidebarSelection
    let titleBar: CGFloat
    let toggleLeading: CGFloat
    let hide: () -> Void
    @Environment(IdentityModel.self) private var identity
    @Environment(Crew.self) private var crew
    @Environment(ReviewModel.self) private var review
    @Environment(TodayModel.self) private var today
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
        default: 0
        }
    }

    @ViewBuilder private func menu(for helper: HelperModel) -> some View {
        Button("Rename…") { editing = .rename(helper) }
        Button("Edit brief…") { editing = .brief(helper) }
        Button(helper.isPaused ? "Resume" : "Pause") { crew.setPaused(helper, !helper.isPaused) }
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

    private var mochiMood: Mascot.Mood {
        let moods = crew.machines.map(\.mood)
        return [.working, .trouble, .asking].first(where: moods.contains) ?? .calm
    }
}

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
    var detail: String?
    let isSelected: Bool
    var dimsIcon = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        let side = Self.iconSide * scale
        HStack(spacing: Space.s) {
            Group {
                switch icon {
                case .symbol(let name):
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

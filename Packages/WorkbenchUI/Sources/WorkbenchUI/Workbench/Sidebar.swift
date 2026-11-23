import AppKit
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
            .page(.deals, symbol: "rectangle.3.group"),
        ]),
        Section(
            title: "Crew",
            entries: [
                .helper(.mochi), .page(.crew, symbol: "rectangle.grid.2x2"), .machines,
                .page(.review, symbol: "checkmark.circle"), .page(.catalog, symbol: "person.crop.rectangle.stack"),
            ]),
    ]

    static var pages: [SidebarSelection] {
        sections.flatMap(\.entries).compactMap { entry in
            switch entry {
            case .page(let page, _), .helper(let page): page
            case .machines: nil
            }
        }
    }

    static func symbol(of page: SidebarSelection) -> String? {
        if page == .usage { return "chart.xyaxis.line" }
        if page == .settings { return "gearshape" }
        for case .page(let listed, let symbol) in sections.flatMap(\.entries) where listed == page { return symbol }
        return nil
    }

    static func lists(_ page: SidebarSelection) -> Bool {
        if case .machine = page { return true }
        if page == .usage || page == .settings { return true }
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
    var openInNewTab: (SidebarSelection) -> Void = { _ in }
    @Environment(IdentityModel.self) private var identity
    @Environment(Crew.self) private var crew
    @Environment(ReviewModel.self) private var review
    @Environment(TodayModel.self) private var today
    @Environment(TeamCatalogModel.self) private var catalog
    @Environment(PlanUsage.self) private var planUsage
    @Environment(ModelSettings.self) private var models
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
            usageRow
            settingsRow
        }
        .background(.sidebarFill)
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
                "Its \(helper.spec.itemsNoun), your marks on them and its settings are deleted. Its calls stay on the Usage page."
            )
        }
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
            .contextMenu { newTab(page) }
        case .helper(let page):
            row(page, role: page.role) {
                SidebarRow(
                    title: page.title,
                    icon: page.look.map { .face($0, page == .mochi ? mochiMood : .calm) } ?? .symbol("circle"),
                    isSelected: selection == page)
            }
            .contextMenu { newTab(page) }
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

    private func row(
        _ page: SidebarSelection, role: String? = nil, @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            go(page)
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
        case .day: today.needsCount
        case .review: review.items.count
        case .catalog: catalog.teammates.count + catalog.teammatesDays.count
        default: 0
        }
    }

    private func go(_ page: SidebarSelection) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true { openInNewTab(page) } else { selection = page }
    }

    private func newTab(_ page: SidebarSelection) -> some View {
        Button("Open in new tab") { openInNewTab(page) }
    }

    @ViewBuilder private func menu(for helper: HelperModel) -> some View {
        newTab(.machine(helper.machine.id))
        Divider()
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

    private var planWindow: PlanLimits.Window? {
        guard models.billing == .plan, let limits = planUsage.limits else { return nil }
        return limits.fiveHour ?? limits.week
    }

    private var usageRow: some View {
        Button {
            go(.usage)
        } label: {
            HStack(spacing: Space.s) {
                PlanRing(window: planWindow, size: 20)
                Text(SidebarSelection.usage.title).lineLimit(1).sidebarTitle(isSelected: selection == .usage)
                Spacer()
                if let planWindow {
                    Text(PlanRing.percent(planWindow.used)).textStyle(.callout, digits: true)
                        .foregroundStyle(.sidebarLabel)
                }
            }
            .padding(.horizontal, Space.s).frame(minHeight: 30).contentShape(.rect)
        }
        .buttonStyle(SidebarRowStyle(isSelected: selection == .usage))
        .padding(.horizontal, Space.s)
        .help(usageSummary)
        .accessibilityLabel(SidebarSelection.usage.title)
        .contextMenu { newTab(.usage) }
    }

    private var usageSummary: String {
        guard models.billing == .plan, let limits = planUsage.limits else { return SidebarSelection.usage.title }
        return "Claude plan\n" + limits.summary
    }

    private var settingsRow: some View {
        Button {
            go(.settings)
        } label: {
            HStack(spacing: Space.s) {
                Monogram(name: identity.identity.hasName ? identity.identity.name : "You")
                Text(identity.identity.hasName ? identity.identity.name : "You").lineLimit(1)
                    .sidebarTitle(isSelected: false)
                Spacer()
                SidebarSymbol(name: "gearshape", isSelected: false)
            }
            .padding(Space.s)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowStyle(isSelected: selection == .settings))
        .contextMenu { newTab(.settings) }
        .padding(Space.s)
        .help("Settings (⌘,)")
    }

    private var mochiMood: Mascot.Mood {
        let moods = crew.machines.map(\.mood)
        return [.working, .trouble, .asking].first(where: moods.contains) ?? .calm
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
        HStack(spacing: Space.s) {
            iconView
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

    private var iconView: some View {
        let side = Self.iconSide * scale
        return Group {
            switch icon {
            case .symbol(let name):
                SidebarSymbol(name: name, isSelected: isSelected, size: Self.symbolSize * scale)
            case .face(let look, let mood): Mascot(look: look, size: side, mood: mood)
            }
        }
        .frame(width: side, height: side)
        .opacity(dimsIcon ? 0.5 : 1)
    }
}

struct SidebarSymbol: View {
    let name: String
    let isSelected: Bool
    var size: CGFloat?
    @Environment(\.isSidebarRowHot) private var isHot

    var body: some View {
        let weight: Font.Weight = isHot ? .bold : .medium
        Image(systemName: name)
            .font(size.map { .system(size: $0, weight: weight) } ?? .body.weight(weight))
            .foregroundStyle(isHot ? Color.sidebarHotIcon : isSelected ? .sidebarSelectedText : .sidebarIcon)
    }
}

extension EnvironmentValues {
    @Entry var isSidebarRowHot = false
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
            .environment(\.isSidebarRowHot, isHovered || configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .pointerStyle(.link)
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
                Picker("Reads", selection: $template) {
                    ForEach(MachineTemplate.addable) { Text($0.reads ?? $0.role).tag($0) }
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
                    "A new brief is a new version. Its marks and trust start again; the old version's stay on the Usage page."
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

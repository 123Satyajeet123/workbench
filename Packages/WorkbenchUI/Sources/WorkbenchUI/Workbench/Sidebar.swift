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
        ]),
        Section(
            title: "Crew",
            entries: [
                .helper(.mochi), .page(.crew, symbol: "rectangle.grid.2x2"), .machines,
                .page(.review, symbol: "checkmark.circle"),
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
    let titleBar: CGFloat
    let toggleLeading: CGFloat
    let isRail: Bool
    let toggle: () -> Void
    var openInNewTab: (SidebarSelection) -> Void = { _ in }
    @Environment(IdentityModel.self) private var identity
    @Environment(Crew.self) private var crew
    @Environment(ReviewModel.self) private var review
    @Environment(TodayModel.self) private var today
    @Environment(PlanUsage.self) private var planUsage
    @Environment(ModelSettings.self) private var models
    @State private var editing: MachineEdit?
    @State private var deleting: HelperModel?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: isRail ? .center : .leading, spacing: 0) {
                    ForEach(SidebarLayout.sections.indices, id: \.self) { index in
                        section(SidebarLayout.sections[index])
                    }
                }
                .padding(.horizontal, Space.s)
                .padding(.top, Space.m)
                .padding(.bottom, Space.s)
            }
            .scrollClipDisabled(isRail)
            usageRow
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
                "Its \(helper.spec.itemsNoun), your marks on them and its settings are deleted. Its calls stay on the Usage page."
            )
        }
    }

    private var topRow: some View {
        HStack {
            if !isRail { SidebarToggle(isShown: true, toggle: toggle).padding(.leading, toggleLeading) }
            Spacer()
        }
        .frame(height: titleBar)
        .background(.sidebarFill)
        .contentShape(.rect)
        .gesture(WindowDragGesture())
    }

    private func section(_ section: SidebarLayout.Section) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = section.title {
                if isRail {
                    Divider().padding(.horizontal, Space.xs).padding(.bottom, Space.s)
                } else {
                    label(title, addsMachine: section.entries.contains(.machines))
                }
            }
            ForEach(section.entries.indices, id: \.self) { index in entry(section.entries[index]) }
        }
        .padding(.top, section.title == nil ? 1 : isRail ? Space.s : Space.l)
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
            row(page, title: page.title) {
                SidebarRow(
                    title: page.title, icon: .symbol(symbol), detail: count > 0 ? count.formatted() : nil,
                    isSelected: selection == page, isRail: isRail, showsDot: count > 0)
            }
            .contextMenu { newTab(page) }
        case .helper(let page):
            row(page, title: page.title, role: page.role) {
                SidebarRow(
                    title: page.title,
                    icon: page.look.map { .face($0, page == .mochi ? mochiMood : .calm) } ?? .symbol("circle"),
                    isSelected: selection == page, isRail: isRail)
            }
            .contextMenu { newTab(page) }
        case .machines:
            ForEach(crew.crew, id: \.machine.id) { helper in
                let page = SidebarSelection.machine(helper.machine.id)
                row(page, title: helper.name, role: MachineTemplate.of(helper.machine)?.role) {
                    SidebarRow(
                        title: helper.name, icon: .face(.of(helper.machine), helper.mood),
                        detail: helper.isPaused ? "Paused" : nil, isSelected: selection == page, isRail: isRail,
                        dimsIcon: helper.isPaused)
                }
                .contextMenu { menu(for: helper) }
            }
            if isRail {
                Button {
                    editing = .new
                } label: {
                    SidebarRow(title: "Add a machine", icon: .symbol("plus"), isSelected: false, isRail: true)
                }
                .buttonStyle(SidebarRowStyle(isSelected: false))
                .railName("Add a machine", isRail: true)
            }
        }
    }

    private func row(
        _ page: SidebarSelection, title: String, role: String? = nil, @ViewBuilder label: () -> some View
    ) -> some View {
        Button {
            go(page)
        } label: {
            label()
        }
        .buttonStyle(SidebarRowStyle(isSelected: selection == page))
        .help(isRail ? "" : role ?? "")
        .railName(title, isRail: isRail)
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
            if isRail {
                PlanRing(window: planWindow, size: 28).frame(maxWidth: .infinity).frame(height: 40).contentShape(.rect)
            } else {
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
        }
        .buttonStyle(SidebarRowStyle(isSelected: selection == .usage))
        .padding(.horizontal, isRail ? Space.xs : Space.s)
        .help(isRail ? "" : usageSummary)
        .railName(usageSummary, isRail: isRail)
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
            if isRail {
                SidebarRow(
                    title: "Settings", icon: .symbol("gearshape"), isSelected: selection == .settings, isRail: true)
            } else {
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
        }
        .buttonStyle(SidebarRowStyle(isSelected: selection == .settings))
        .contextMenu { newTab(.settings) }
        .padding(isRail ? Space.xs : Space.s)
        .help(isRail ? "" : "Settings (⌘,)")
        .railName("Settings", isRail: isRail)
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
    private static let railSide: CGFloat = 36

    let title: String
    let icon: Icon
    var detail: String?
    let isSelected: Bool
    var isRail = false
    var showsDot = false
    var dimsIcon = false
    @Environment(\.uiScale) private var scale

    var body: some View {
        if isRail {
            iconView
                .frame(maxWidth: .infinity)
                .frame(height: Self.railSide * scale)
                .overlay(alignment: .topTrailing) {
                    if showsDot { Circle().fill(.accentFill).frame(width: 6, height: 6).padding(Space.xs) }
                }
                .contentShape(.rect)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title)
        } else {
            row
        }
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

    private var row: some View {
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

private struct RailName: ViewModifier {
    let title: String
    let isRail: Bool
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .onHover { isHovered = $0 }
            .overlay {
                if isRail, isHovered {
                    GeometryReader { box in
                        label.frame(height: box.size.height).offset(x: box.size.width + Space.m)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
    }

    private var label: some View {
        Text(title)
            .textStyle(.callout, weight: .medium)
            .foregroundStyle(.bodyText)
            .fixedSize()
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(.pageFill, in: .rect(cornerRadius: Radius.control))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).stroke(.dividerLine))
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    }
}

extension View {
    fileprivate func railName(_ title: String, isRail: Bool) -> some View {
        modifier(RailName(title: title, isRail: isRail))
    }
}

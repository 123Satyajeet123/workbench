import SwiftUI

enum SettingsSection: String, CaseIterable, Hashable {
    case general, team, appearance, notch, notifications, capture, webResearch, startup

    static let groups: [(title: String?, sections: [SettingsSection])] = [
        (nil, [.general, .team, .appearance, .notch, .notifications]),
        ("This computer", [.capture, .webResearch, .startup]),
    ]

    var title: String {
        switch self {
        case .general: "General"
        case .team: "Team"
        case .appearance: "Appearance"
        case .notch: "Notch"
        case .notifications: "Notifications"
        case .capture: "Capture"
        case .webResearch: "Web research"
        case .startup: "App behavior"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .team: "person.3"
        case .appearance: "paintpalette"
        case .notch: "rectangle.topthird.inset.filled"
        case .notifications: "bell"
        case .capture: "eye"
        case .webResearch: "globe"
        case .startup: "power"
        }
    }

    static func matching(_ query: String) -> [SettingsSection] {
        let typed = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !typed.isEmpty else { return allCases }
        return allCases.filter { section in
            let text =
                ([section.title] + SettingsItem.all.filter { $0.section == section }.flatMap { [$0.title, $0.words] })
                .joined(separator: " ").lowercased()
            let words = text.split { !$0.isLetter && !$0.isNumber }
            return typed.allSatisfy { part in words.contains { $0.hasPrefix(part) } }
        }
    }
}

struct SettingsPage: View {
    @Environment(Navigation.self) private var navigation
    @State private var query = ""

    var body: some View {
        HStack(spacing: 0) {
            sectionList.frame(width: 240)
            Rectangle().fill(.dividerLine).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                Text(navigation.settingsSection.title).textStyle(.largeTitle, weight: .bold)
                    .padding(.horizontal, Space.page).padding(.top, Space.page).padding(.bottom, Space.s)
                SettingsSectionView(section: navigation.settingsSection)
                    .id(navigation.settingsSection)
                    .frame(maxWidth: Page<EmptyView, EmptyView>.columnWidth + 2 * Space.l)
                    .padding(.horizontal, Space.page - Space.l)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.pageFill)
    }

    private var sectionList: some View {
        let shown = Set(SettingsSection.matching(query))
        return VStack(alignment: .leading, spacing: Space.xs) {
            Text("Your settings").textStyle(.title3, weight: .bold).padding(.horizontal, Space.s)
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass").foregroundStyle(.supporting)
                TextField("Search settings…", text: $query).textFieldStyle(.plain)
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(.calloutFill, in: .capsule)
            .padding(.vertical, Space.s)
            ForEach(SettingsSection.groups, id: \.sections) { group in
                let sections = group.sections.filter(shown.contains)
                if !sections.isEmpty {
                    if let title = group.title {
                        Text(title).textStyle(.callout).foregroundStyle(.supporting)
                            .padding(.horizontal, Space.s).padding(.top, Space.m)
                    }
                    ForEach(sections, id: \.self) { row($0) }
                }
            }
            if shown.isEmpty {
                Text("No setting matches “\(query)”.").foregroundStyle(.supporting).padding(.horizontal, Space.s)
            }
            Spacer()
        }
        .padding(Space.m)
        .background(.sidebarFill)
    }

    private func row(_ section: SettingsSection) -> some View {
        let isSelected = navigation.settingsSection == section
        return Button {
            navigation.settingsSection = section
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: section.symbol).frame(width: 20)
                Text(section.title)
            }
            .foregroundStyle(isSelected ? Color.sidebarSelectedText : .sidebarText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s).padding(.vertical, Space.s)
            .background(isSelected ? Color.selectedFill : .clear, in: .rect(cornerRadius: Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SettingsItem {
    let title: String
    let section: SettingsSection
    let words: String

    static let all = [
        SettingsItem(title: "Your name", section: .general, words: "name you founder"),
        SettingsItem(title: "Model", section: .general, words: "read with claude opus sonnet codex ai"),
        SettingsItem(title: "Billing and API key", section: .general, words: "bill to plan anthropic api key pay"),
        SettingsItem(
            title: "Plan conditions", section: .general,
            words: "confirm conditions terms training reader signed subscription consent"),
        SettingsItem(title: "Demo", section: .general, words: "demo synthetic sample example profile switch back data"),
        SettingsItem(
            title: "Team name and people", section: .team, words: "team people person role add remove members"),
        SettingsItem(title: "Team folder", section: .team, words: "share sharing folder icloud sync"),
        SettingsItem(title: "Theme", section: .appearance, words: "appearance dark mode light system colour color"),
        SettingsItem(
            title: "Show in the notch", section: .notch,
            words: "island top screen camera recording reading review queue hide"),
        SettingsItem(title: "When nothing is happening", section: .notch, words: "idle claude plan ring usage"),
        SettingsItem(
            title: "Reminders", section: .notifications, words: "digest morning brief notifications weekly mochi"),
        SettingsItem(title: "Most a day", section: .notifications, words: "notifications how many limit cap daily"),
        SettingsItem(
            title: "Quiet hours", section: .notifications, words: "notifications quiet night disturb from until"),
        SettingsItem(title: "Open at login", section: .startup, words: "startup login launch start"),
        SettingsItem(
            title: "Capture sources", section: .capture,
            words: "screen files calls microphone whatsapp telegram mail switches capture"),
        SettingsItem(title: "Web research", section: .webResearch, words: "search provider claims queries internet"),
        SettingsItem(
            title: "Source health", section: .capture, words: "health ready permission problem broken access sources"),
        SettingsItem(
            title: "Record calls automatically", section: .capture,
            words: "spot detect calls always record zoom meet teams microphone"),
        SettingsItem(
            title: "Save recordings in", section: .capture, words: "folder location where calls recordings saved echo"),
        SettingsItem(title: "Never capture", section: .capture, words: "deny block exclude private apps websites"),
        SettingsItem(title: "Delete WhatsApp messages", section: .capture, words: "whatsapp delete erase remove data"),
        SettingsItem(title: "Kept today", section: .capture, words: "log activity windows delete history"),
    ]
}

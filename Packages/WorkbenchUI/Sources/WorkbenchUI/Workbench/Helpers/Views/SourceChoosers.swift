import LocalSources
import SwiftUI
import WorkbenchCore

struct SourceChooser: View {
    let model: HelperModel

    var body: some View {
        if let source = model.source as? WhatsAppSource {
            GroupChooser(model: model, source: source)
        } else if let source = model.source as? PageSource {
            SiteChooser(model: model, source: source)
        } else if let source = model.source as? MailSource {
            LabelChooser(model: model, source: source)
        } else if let source = model.source as? TelegramSource {
            TelegramChooser(model: model, source: source)
        }
    }
}

struct LabelChooser: View {
    let model: HelperModel
    let source: MailSource
    @State private var typed = MailSource.defaultLabel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "In Gmail, make a label for deal mail and a filter that puts it there. \(model.name) reads a thread only while you have it open in that label, with the Workbench browser extension on. It reads no other mail."
            )
            .foregroundStyle(.supporting)
            HStack {
                TextField("Label name, as in Gmail", text: $typed).frame(maxWidth: 260)
                Button("Read this label") {
                    model.attempt("save the label") { try source.choose(typed) }
                    model.reload()
                }
                .buttonStyle(.primary)
            }
        }
    }
}

struct SiteChooser: View {
    let model: HelperModel
    let source: PageSource
    @State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "Name the sites \(model.name) reads, such as linkedin.com or x.com. It reads only their text, only the day you ask."
            )
            .foregroundStyle(.supporting)
            HStack {
                TextField("linkedin.com, x.com", text: $typed).frame(maxWidth: 360)
                Button("Use these sites") {
                    model.attempt("save the sites") { try source.choose(typed) }
                    model.reload()
                }
                .buttonStyle(.primary).disabled(typed.isEmpty)
            }
        }
    }
}

struct GroupChooser: View {
    let model: HelperModel
    let source: WhatsAppSource
    @State private var scope: ChatScope?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Choose what \(model.name) reads. It reads only those chats, and only the day you ask it to.")
                .foregroundStyle(.supporting)
            Picker("Reads", selection: Binding(get: { scope ?? current }, set: { scope = $0 })) {
                ForEach(ChatScope.allCases, id: \.self) { Text("\($0.title) · \($0.line)").tag($0) }
            }
            .pickerStyle(.radioGroup).labelsHidden()
            switch scope ?? current {
            case .one: OneGroupChooser(model: model, source: source)
            case .several: SeveralChatsChooser(model: model, source: source)
            case .every: EveryChatChooser(model: model, source: source)
            }
            if source.isChanging, let current = model.chosenSource {
                Button("Keep \(current)", action: source.keep)
            }
        }
    }

    private var current: ChatScope {
        source.readsEveryChat ? .every : source.isSeveral ? .several : .one
    }
}

enum ChatScope: CaseIterable {
    case one, several, every

    var title: String {
        switch self {
        case .one: "One group"
        case .several: "Several chats"
        case .every: "Every chat"
        }
    }

    var line: String {
        switch self {
        case .one: "your team's WhatsApp group"
        case .several: "groups whose name holds some words"
        case .every: "all your chats, personal ones too"
        }
    }
}

private struct OneGroupChooser: View {
    let model: HelperModel
    let source: WhatsAppSource
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if source.groups.isEmpty {
                Button("Show my WhatsApp groups") { model.attempt("list your WhatsApp groups", source.loadGroups) }
                    .buttonStyle(.primary)
            } else {
                TextField("Search your groups", text: $query, prompt: Text("Search your groups"))
                    .textFieldStyle(.roundedBorder)
                let found = FuzzySearch.filter(source.groups, by: query, name: \.name)
                if found.isEmpty {
                    Text("No group matches “\(query)”.").foregroundStyle(.supporting)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(found) { group in
                        HStack {
                            Text(group.name).lineLimit(1)
                            Spacer()
                            Button("Choose") {
                                model.attempt("save the group") { try source.choose(group) }
                                model.reload()
                            }
                            .buttonStyle(.ghost).foregroundStyle(.linkText)
                        }
                        .padding(.vertical, Space.xs)
                        if group.id != found.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct EveryChatChooser: View {
    let model: HelperModel
    let source: WhatsAppSource
    @Environment(ModelSettings.self) private var models

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "All your WhatsApp chats, groups and direct ones, family and personal too, and chats you start later. Each reading sends that day's messages from every chat to \(models.choice.title)."
            )
            .foregroundStyle(.supporting)
            Button("Read every chat") {
                model.attempt("save the chats", source.chooseEveryChat)
                model.reload()
            }
            .buttonStyle(.primary).disabled(source.readsEveryChat)
        }
    }
}

struct SeveralChatsChooser: View {
    let model: HelperModel
    let source: WhatsAppSource
    @State private var words = ""
    @State private var direct = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("You see every chat before any is read.").foregroundStyle(.supporting)
            TextField("Words in the group names, such as Acme", text: $words)
                .textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                .onSubmit(find)
            Toggle("Also read direct chats with the people in those groups", isOn: $direct).toggleStyle(.checkbox)
            Button("Find chats", action: find).buttonStyle(.primary).disabled(isEmpty)
            if !source.matching.isEmpty {
                let groups = source.matching.filter(\.isGroup).count
                Text(
                    "\(groups) groups and \(source.matching.count - groups) direct chats: \(source.matching.prefix(12).map(\.name).joined(separator: ", "))\(source.matching.count > 12 ? ", …" : "")"
                )
                .textStyle(.callout).foregroundStyle(.supporting)
                Button("Read these \(source.matching.count) chats") {
                    model.attempt("save the chats") { try source.choose(source.matching) }
                    model.reload()
                }
                .buttonStyle(.primary)
            }
        }
    }

    private var isEmpty: Bool { words.trimmingCharacters(in: .whitespaces).isEmpty }

    private func find() {
        guard !isEmpty else { return }
        model.attempt("list the chats") {
            try source.preview(ChatSelection(nameContains: words, directWithMembers: direct))
        }
    }
}

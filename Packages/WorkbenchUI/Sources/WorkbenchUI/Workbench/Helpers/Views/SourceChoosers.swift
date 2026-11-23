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
        } else if model.source is NewsSource {
            NewsChooser(model: model)
        } else if model.source is OutboundSource {
            OutboundChooser(model: model)
        } else if let source = model.source as? TelegramSource {
            TelegramChooser(model: model, source: source)
        }
    }
}

/// The Gmail label a mail machine reads. Only threads opened in this label are kept; mail elsewhere stays in Gmail.
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
            SourceHealthMark(source: .mail)
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

/// The sites a page machine reads. Only these sites' text is ever sent; the rest stays on the Mac.
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
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Choose what \(model.name) reads. It reads only those chats, and only the day you ask it to.")
                .foregroundStyle(.supporting)
            if !source.chats.isEmpty { ChosenChats(model: model, source: source) }
            Card(title: "One chat", symbol: "person.3") {
                Text("Your team's WhatsApp group.")
                    .foregroundStyle(.supporting)
                if source.groups.isEmpty && source.direct.isEmpty {
                    Button("Show my WhatsApp chats") { model.attempt("list your WhatsApp chats", source.loadGroups) }
                        .buttonStyle(.primary)
                    if let problem = source.pullProblem {
                        Text(problem).textStyle(.callout).foregroundStyle(.supporting)
                    }
                } else {
                    TextField("Search your chats", text: $query, prompt: Text("Search your chats"))
                        .textFieldStyle(.roundedBorder)
                    let found = FuzzySearch.filter(source.groups + source.direct, by: query, name: \.name)
                    if found.isEmpty {
                        Text("No chat matches “\(query)”.").foregroundStyle(.supporting)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(found) { chat in
                            HStack {
                                Text(chat.name).lineLimit(1)
                                Spacer()
                                Button("Choose") {
                                    model.attempt("save the chat") { try source.choose(chat) }
                                    model.reload()
                                }
                                .buttonStyle(.ghost).foregroundStyle(.linkText)
                            }
                            .padding(.vertical, Space.xs)
                            if chat.id != found.last?.id { Divider() }
                        }
                    }
                }
            }
            .onDisappear { source.closeDiscovery() }
            SeveralChatsChooser(model: model, source: source)
            if source.isChanging, let current = model.chosenSource {
                Button("Keep \(current)", action: source.keep)
            }
        }
    }
}

/// Several chats by a rule: groups whose name holds some words, and direct chats with people in them. The founder
/// sees every chat the rule chooses before any is read.
struct SeveralChatsChooser: View {
    let model: HelperModel
    let source: WhatsAppSource
    @State private var words = ""
    @State private var direct = true

    var body: some View {
        Card(title: "Several chats", symbol: "text.magnifyingglass") {
            Text("Groups whose name holds some words. You see every chat before any is read.")
                .foregroundStyle(.supporting)
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

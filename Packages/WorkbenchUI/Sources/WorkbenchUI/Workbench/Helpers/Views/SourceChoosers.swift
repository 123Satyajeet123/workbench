import LocalSources
import SwiftUI
import WorkbenchCore

/// The setup a machine needs before it can read, by the kind of source it has.
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
            HStack {
                TextField("Label name, as in Gmail", text: $typed).frame(maxWidth: 260)
                Button("Read this label") {
                    model.attempt("save the label") { try source.choose(typed) }
                    model.reload()
                }
                .buttonStyle(.borderedProminent)
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
                .buttonStyle(.borderedProminent).disabled(typed.isEmpty)
            }
        }
    }
}

struct GroupChooser: View {
    let model: HelperModel
    let source: WhatsAppSource

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "Choose your team's WhatsApp group. \(model.name) reads only that group, and only the day you ask it to read."
            )
            .foregroundStyle(.supporting)
            if source.groups.isEmpty {
                Button("Show my WhatsApp groups") { model.attempt("list your WhatsApp groups", source.loadGroups) }
                    .buttonStyle(.borderedProminent)
            }
            ForEach(source.groups) { group in
                HStack {
                    Text(group.name)
                    Spacer()
                    Button("Choose") {
                        model.attempt("save the group") { try source.choose(group) }
                        model.reload()
                    }
                }
                Divider()
            }
            SeveralChatsChooser(model: model, source: source)
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
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Or read several chats").textStyle(.headline)
            HStack {
                TextField("Groups whose name holds", text: $words).frame(maxWidth: 260)
                Toggle("and direct chats with their members", isOn: $direct)
                Button("Find chats") {
                    model.attempt("list the chats") {
                        try source.preview(ChatSelection(nameContains: words, directWithMembers: direct))
                    }
                }
                .disabled(words.trimmingCharacters(in: .whitespaces).isEmpty)
            }
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
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

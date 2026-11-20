import SwiftUI
import WorkbenchCore

/// One fact or finding as one line, with its actions. Open it to read the message it came from and to see the chat
/// line.
struct FactLine: View {
    let item: Item
    let model: TodayModel
    /// Why the line is here, in a word: "Overdue", "Asks you". Nil on a list that needs no reason.
    var flag: String?
    var flagTone: Tone = .attention

    @State private var isOpen = false
    @State private var chat: [ChatLine]?
    @State private var chatProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Button(action: toggle) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.s) {
                            if let flag {
                                Text(flag).textStyle(.caption, weight: .semibold).foregroundStyle(flagTone.color)
                            }
                            Text(model.title(of: item)).multilineTextAlignment(.leading)
                        }
                        if !meta.isEmpty { Text(meta).textStyle(.callout).foregroundStyle(.supporting) }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the message it came from")
                Spacer(minLength: Space.m)
                FactActions(items: [item], summary: model.title(of: item), model: model)
            }
            if isOpen { source }
        }
        .padding(.vertical, Space.xs)
    }

    /// Person, project and due day, in the words a founder uses.
    private var meta: String {
        var parts = [item["person"], item["project"]].filter { !$0.isEmpty }
        if let due = item.dueDay {
            parts.append("due \(due.start.formatted(.dateTime.weekday(.abbreviated).day().month()))")
        }
        if !item["reason"].isEmpty { parts.append(item["reason"]) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var source: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("“\(item.quote)” · \(item.start.formatted(date: .abbreviated, time: .shortened))")
                .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            if item.citeFirst > 0 { chatLines }
        }
        .padding(.leading, Space.m)
    }

    @ViewBuilder private var chatLines: some View {
        if let chat {
            ForEach(chat) { line in
                Text("\(line.time.formatted(date: .omitted, time: .shortened))  \(line.text)")
                    .textStyle(.callout, weight: line.isCited ? .semibold : nil)
                    .foregroundStyle(line.isCited ? Color.primary : .supporting).textSelection(.enabled)
            }
            if chat.isEmpty {
                Text("This line is not in the chat any more.").textStyle(.callout).foregroundStyle(.supporting)
            }
        } else if let chatProblem {
            Text(chatProblem).textStyle(.callout).foregroundStyle(Tone.bad.color)
        } else {
            Button("See the chat line", systemImage: "bubble.left.and.text.bubble.right", action: loadChat)
                .buttonStyle(.borderless).textStyle(.callout)
        }
    }

    private func toggle() { isOpen.toggle() }

    private func loadChat() {
        Task {
            do {
                chat = try await model.chatLines(around: item)
            } catch {
                chatProblem = "Could not read the chat: \(error.localizedDescription)"
            }
        }
    }
}

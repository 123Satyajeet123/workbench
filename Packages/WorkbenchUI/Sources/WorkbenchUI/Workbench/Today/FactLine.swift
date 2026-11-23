import SwiftUI
import WorkbenchCore

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
                                .strikethrough(isDone, color: .secondary)
                                .foregroundStyle(isDone ? Color.supporting : .bodyText)
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
            if item.task == Revisit.task {
                revisitNews
            } else if isOpen {
                source
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var isDone: Bool { model.isDone([item]) }

    private var meta: String {
        var parts = [item["person"], item["project"], item["company"], item["event"], item["feed"]].filter {
            !$0.isEmpty
        }
        if let due = item.dueDay {
            parts.append("due \(due.start.formatted(.dateTime.weekday(.abbreviated).day().month()))")
        }
        if !item["reason"].isEmpty { parts.append(item["reason"]) }
        return parts.joined(separator: " · ")
    }

    /// The news about a passed deal's company since the pass, for a revisit.
    private var related: [Item] { item.id.flatMap { model.passedNews[$0] } ?? [] }

    /// What the company did since the investor passed: shown with the revisit, not behind a click.
    @ViewBuilder private var revisitNews: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(related) { SignalLine(signal: $0) }
            if related.isEmpty {
                Text("No news about it since you passed.").textStyle(.callout).foregroundStyle(.supporting)
            }
        }
        .padding(.leading, Space.m)
    }

    @ViewBuilder private var source: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(item.quotedWords) · \(item.start.formatted(date: .abbreviated, time: .shortened))")
                .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            if item.citeFirst > 0, item.source != .web { chatLines }
        }
        .padding(.leading, Space.m)
    }

    @ViewBuilder private var chatLines: some View {
        if let chat {
            ForEach(chat) { line in
                Text("\(line.time?.formatted(date: .omitted, time: .shortened) ?? "")  \(line.text)")
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
                .buttonStyle(.ghost).textStyle(.callout)
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

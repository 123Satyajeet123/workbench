import SwiftUI
import WorkbenchCore

struct FactLine: View {
    let item: Item
    let model: TodayModel
    /// The field the list around the line is grouped by: its heading says it, so the line does not.
    var grouping: String?

    @State private var isOpen = false
    @State private var chat: [ChatLine]?
    @State private var chatProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Button(action: toggle) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(model.title(of: item)).multilineTextAlignment(.leading)
                                .strikethrough(isDone, color: .secondary)
                                .foregroundStyle(isDone ? Color.supporting : .bodyText)
                            if !meta.isEmpty { Text(meta).textStyle(.callout).foregroundStyle(.supporting) }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the message it came from")
                    FactHomeLine(item: item, surface: .today)
                }
                Spacer(minLength: Space.m)
                FactActions(items: [item], summary: model.title(of: item), model: model)
            }
            if passedNews != nil {
                revisitNews
            } else if isOpen {
                source
            }
        }
        .padding(.vertical, Space.xs)
    }

    private var isDone: Bool { model.isDone([item]) }

    private var meta: String {
        var parts = ["person", "project", "company", "event", "feed"].filter { $0 != grouping }.map { item[$0] }
            .filter { !$0.isEmpty }
        if let due = item.dueDay {
            parts.append("due \(due.start.formatted(.dateTime.weekday(.abbreviated).day().month()))")
        }
        if !item["reason"].isEmpty { parts.append(item["reason"]) }
        return parts.joined(separator: " · ")
    }

    /// The news about a passed deal's company since the pass, for a revisit.
    private var passedNews: [Item]? { item.id.flatMap { model.passedNews[$0] } }

    private var related: [Item] { passedNews ?? [] }

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

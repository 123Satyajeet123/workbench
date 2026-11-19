import SwiftUI
import WorkbenchCore

/// The team's deals as a board, one column per stage. A deal opens beside the board.
struct DealsPage: View {
    @Environment(DealsModel.self) private var deals
    @State private var open: String?
    @State private var newTitle = ""

    var body: some View {
        Page(title: SidebarSelection.deals.title, subtitle: subtitle) {
            if let problem = deals.problem { ProblemBanner(text: problem, dismiss: deals.dismissProblem) }
            AskBox()
            HStack {
                TextField("New deal: company name", text: $newTitle).frame(maxWidth: 280)
                    .onSubmit(create)
                Button("Add deal", action: create).disabled(newTitle.cleaned == nil)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: deals.refresh)
            }
            HStack(alignment: .top, spacing: Space.l) {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Space.m) {
                        ForEach(deals.stages, id: \.self) { stage in
                            StageColumn(stage: stage, open: $open)
                        }
                    }
                }
                if let id = open, let deal = deals.deal(id) {
                    DealDetail(deal: deal, close: { open = nil }).frame(width: 340)
                }
            }
        }
        .onAppear(perform: deals.refresh)
    }

    private var subtitle: String {
        "\(deals.deals.count) deals. Your moves and notes go to your team's folder; items only to people who can already read them."
    }

    private func create() {
        open = deals.create(title: newTitle)
        newTitle = ""
    }
}

private struct StageColumn: View {
    let stage: String
    @Binding var open: String?
    @Environment(DealsModel.self) private var deals

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("\(stage) · \(deals.deals(in: stage).count)").textStyle(.headline)
            ForEach(deals.deals(in: stage)) { deal in
                Button {
                    open = deal.id
                } label: {
                    DealCard(deal: deal)
                }.buttonStyle(.plain)
            }
        }
        .frame(width: 190, alignment: .topLeading)
    }
}

private struct DealCard: View {
    let deal: WorkObject

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(deal.title).fontWeight(.medium)
            if deal.stages.count > 1 {
                Label("Two stages: \(deal.stages.joined(separator: " and "))", systemImage: "exclamationmark.triangle")
                    .textStyle(.caption).foregroundStyle(Tone.attention.color)
            }
            Text(summary).textStyle(.caption).foregroundStyle(.supporting)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
    }

    private var summary: String {
        [deal.holder.map { "held by \($0)" }, count(deal.items.count, "item"), count(deal.notes.count, "note")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func count(_ number: Int, _ noun: String) -> String {
        "\(number) \(noun)\(number == 1 ? "" : "s")"
    }
}

/// One deal: its stage, who holds it, its items with their quotes, notes and history.
private struct DealDetail: View {
    let deal: WorkObject
    let close: () -> Void
    @Environment(DealsModel.self) private var deals
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Text(deal.title).textStyle(.title3)
                    Spacer()
                    Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                Picker("Stage", selection: Binding(get: { deal.stages.first ?? "" }, set: { deals.move(deal, to: $0) }))
                {
                    ForEach(deals.stages, id: \.self) { Text($0).tag($0) }
                }
                if deal.stages.count > 1 {
                    Text("Two people moved it at the same time: \(deal.stages.joined(separator: " and ")). Choose one.")
                        .textStyle(.callout).foregroundStyle(Tone.attention.color)
                }
                owner
                if !deal.items.isEmpty {
                    Text("Items").textStyle(.headline)
                    ForEach(deal.items, id: \.event.id) { linked in
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(
                                linked.item.columns.compactMap { linked.item.fields[$0] }.filter { !$0.isEmpty }
                                    .joined(separator: " · "))
                            Text(
                                "“\(linked.item.quote)” · \(linked.item.machine), \(linked.item.day), by \(linked.event.author)"
                            )
                            .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                        }
                    }
                }
                Text("Notes").textStyle(.headline)
                ForEach(deal.notes) { note in
                    Text("\(note.author): \(note.text)").textStyle(.callout).textSelection(.enabled)
                }
                HStack {
                    TextField("Add a note", text: $note).onSubmit(addNote)
                    Button("Add", action: addNote).disabled(note.cleaned == nil)
                }
                DisclosureGroup("History") {
                    ForEach(deal.history.reversed()) { event in
                        Text("\(event.author) · \(line(event))").textStyle(.caption).foregroundStyle(.supporting)
                    }
                }
                Button("Archive deal", role: .destructive) {
                    deals.archive(deal)
                    close()
                }
            }
            .padding(Space.m)
        }
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: Radius.card))
    }

    @ViewBuilder private var owner: some View {
        HStack {
            Text(deal.holder.map { "Held by \($0)" } ?? "Nobody holds it").textStyle(.callout)
            if !deal.alsoClaimed.isEmpty {
                Text("also claimed by \(deal.alsoClaimed.joined(separator: ", "))").textStyle(.callout)
                    .foregroundStyle(.supporting)
            }
            Spacer()
            if deal.holder == deals.me || deal.alsoClaimed.contains(deals.me) {
                Button("Let go") { deals.release(deal) }
            } else {
                Button("Take it") { deals.claim(deal) }
            }
        }
    }

    private func addNote() {
        deals.note(deal, note)
        note = ""
    }

    private func line(_ event: WorkEvent) -> String {
        switch event.kind {
        case .create: "made the deal"
        case .title: "named it \(event.text)"
        case .stage: "moved it to \(event.text)"
        case .note: "wrote a note"
        case .link: "linked an item"
        case .claim: "took it"
        case .release: "let it go"
        case .archive: "archived it"
        }
    }
}

/// A question to the team's memory, answered only with citations the founder can open.
private struct AskBox: View {
    @Environment(MemoryModel.self) private var memory
    @State private var question = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                TextField("Ask your memory: what do we know about Acme?", text: $question)
                    .onSubmit(ask)
                Button(memory.asking ? "Asking…" : "Ask", action: ask)
                    .disabled(memory.asking || question.cleaned == nil)
            }
            if let problem = memory.problem { ProblemBanner(text: problem, dismiss: memory.clear) }
            if let answer = memory.answer {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(answer.text ?? "No answer in what you can see (\(answer.searched) entries searched).")
                        .textSelection(.enabled)
                    ForEach(answer.cited) { entry in
                        Text("“\(entry.quote)” · \(entry.source)").textStyle(.callout).foregroundStyle(.supporting)
                            .textSelection(.enabled)
                    }
                }
                .padding(Space.m)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: Radius.card))
            }
        }
    }

    private func ask() {
        let asked = question
        Task { await memory.ask(asked) }
    }
}

import SwiftUI
import WorkbenchCore

struct DealDetail: View {
    let deal: WorkObject
    let move: (WorkObject, String) -> Void
    let close: () -> Void
    @Environment(DealsModel.self) private var deals
    @Environment(RunsModel.self) private var runs
    @State private var note = ""

    private var digest: DealDigest? { deals.digests[deal.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack {
                    Text(deal.title).textStyle(.title3)
                    Spacer()
                    Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly).buttonStyle(.ghost)
                }
                Picker("Stage", selection: Binding(get: { deal.stages.first ?? "" }, set: { move(deal, $0) })) {
                    ForEach(deals.stages, id: \.self) { Text($0).tag($0) }
                }
                if deal.stages.count > 1 {
                    Text("Two people moved it at the same time: \(deal.stages.joined(separator: " and ")). Choose one.")
                        .textStyle(.callout).foregroundStyle(Tone.attention.color)
                }
                owner
                if let open = digest?.action { actionRow(open) }
                if let triage = digest?.triage { WhyCard(triage: triage) }
                ClaimChecksSection(deal: deal)
                if let digest {
                    Text("Captured so far").textStyle(.headline)
                    CaptureRibbon(ribbon: digest.story.ribbon)
                    if !digest.machines.isEmpty {
                        Text("Automation").textStyle(.headline)
                        AutomationStripView(
                            rows: AutomationStrip.rows(for: digest, runs: runs.runs, quality: runs.quality, now: .now))
                    }
                    Text("Timeline").textStyle(.headline)
                    DealTimeline(entries: digest.story.entries)
                }
                items
                notes
                Button("Archive deal", role: .destructive) {
                    deals.archive(deal)
                    close()
                }
            }
            .padding(Space.m)
        }
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }

    private func actionRow(_ action: Item) -> some View {
        HStack {
            ActionLine(action: action)
            Spacer()
            Button("Done") { deals.finishAction(of: deal) }
        }
    }

    @ViewBuilder private var owner: some View {
        HStack {
            Text(deal.holder.map { "Owner: \($0)" } ?? "Nobody holds it").textStyle(.callout)
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

    @ViewBuilder private var items: some View {
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
    }

    @ViewBuilder private var notes: some View {
        Text("Notes").textStyle(.headline)
        ForEach(deal.notes) { note in
            Text("\(note.author): \(note.text)").textStyle(.callout).textSelection(.enabled)
        }
        HStack {
            TextField("Add a note", text: $note).onSubmit(addNote)
            Button("Add", action: addNote).disabled(note.cleaned == nil)
        }
    }

    private func addNote() {
        deals.note(deal, note)
        note = ""
    }
}

struct ActionRequiredForm: View {
    let deal: WorkObject
    let cancel: () -> Void
    @Environment(DealsModel.self) private var deals
    @State private var what = ""
    @State private var due = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("What does \(deal.title) need?").textStyle(.title3)
            TextField("For example: get the cap table from the founder", text: $what).onSubmit(save)
            DatePicker("By when", selection: $due, displayedComponents: .date)
            Text(
                "It becomes an open item with this date. Today lists it and Sentinel watches it. Done moves the deal on."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Require action", action: save).buttonStyle(.primary).disabled(what.cleaned == nil)
            }
        }
        .padding(Space.l).frame(width: 420)
    }

    private func save() {
        deals.requireAction(deal, what: what, due: WorkDay(containing: noon(of: due)))
        cancel()
    }

    private func noon(of date: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}

import AppKit
import SwiftUI
import WorkbenchCore

/// What teammates shared: their days of items, and their machines with each one's record and a way to make it yours.
struct TeamCatalogPage: View {
    let open: (SidebarSelection) -> Void
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        Page(title: SidebarSelection.catalog.title, subtitle: subtitle) {
            if let problem = catalog.problem { ProblemBanner(text: problem, dismiss: catalog.dismissProblem) }
            if catalog.folder == nil {
                Text(
                    "Choose a folder your team syncs (for example in iCloud Drive). Each person shares machines into it."
                )
                .foregroundStyle(.supporting)
                FolderButton()
            } else if catalog.teammates.isEmpty && catalog.teammatesDays.isEmpty {
                Text(
                    "Nothing shared yet. Share a day from a machine's page, or right-click a machine and choose Share with team."
                )
                .foregroundStyle(.supporting)
            }
            if !catalog.teammatesDays.isEmpty {
                Text("Shared days").textStyle(.title3)
                ForEach(catalog.teammatesDays) { SharedDayCard(day: $0) }
                if !catalog.teammates.isEmpty { Text("Machines").textStyle(.title3) }
            }
            ForEach(catalog.teammates) { SharedCard(machine: $0, open: open) }
            if !catalog.unreadable.isEmpty {
                Text("Could not read \(catalog.unreadable.joined(separator: ", ")).").textStyle(.caption)
                    .foregroundStyle(Tone.bad.color)
            }
        }
        .onAppear(perform: catalog.refresh)
    }

    private var subtitle: String {
        catalog.folder.map {
            "Shared in \($0.lastPathComponent). Days go only to people who could already read their source."
        } ?? "Share machines and days with your team."
    }
}

/// One teammate's day from one machine: each item with its quote and the teammate's mark.
private struct SharedDayCard: View {
    let day: SharedDay

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Monogram(name: day.author, size: 22)
                Text(day.machine).textStyle(.headline)
                Text("\(day.day) · shared by \(day.author)").textStyle(.caption).foregroundStyle(.supporting)
            }
            ForEach(day.entries.indices, id: \.self) { index in
                let entry = day.entries[index]
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(day.columns.compactMap { entry.fields[$0] }.filter { !$0.isEmpty }.joined(separator: " · "))
                    Text(
                        "“\(entry.quote)” · \(entry.state == .confirmed ? "confirmed by \(day.author)" : "not reviewed")"
                    )
                    .textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
                }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
    }
}

private struct SharedCard: View {
    let machine: SharedMachine
    let open: (SidebarSelection) -> Void
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Monogram(name: machine.author, size: 22)
                Text(machine.name).textStyle(.headline)
                Text(
                    "by \(machine.author) · \(MachineTemplate.all.first { $0.spec.task == machine.template }?.role ?? machine.template)"
                )
                .textStyle(.caption).foregroundStyle(.supporting)
            }
            Text(machine.spec.brief).textStyle(.callout).foregroundStyle(.supporting).textSelection(.enabled)
            Text(record).textStyle(.callout)
            Button("Adopt") { if let id = catalog.adopt(machine) { open(.machine(id)) } }
                .help("It becomes your machine with this brief. Its trust starts at zero: trust is earned per person.")
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Radius.card))
    }

    private var record: String {
        let r = machine.record
        let audited =
            r.auditedPrecision.map {
                "right on \($0.formatted(.percent.precision(.fractionLength(0)))) of \(r.audited) random checks"
            }
            ?? "no random checks yet"
        let trust: String =
            switch r.trust {
            case .earned(let bound):
                "trusted for \(machine.author): wrong at most \(bound.formatted(.percent.precision(.fractionLength(1))))"
            case .needsMore(let more): "\(more) more held-out answers before trust"
            }
        return "\(r.runs) runs, \(r.kept) kept, \(r.dropped) dropped · \(audited) · \(trust)"
    }
}

/// Chooses the folder the team syncs.
struct FolderButton: View {
    @Environment(TeamCatalogModel.self) private var catalog

    var body: some View {
        Button(catalog.folder == nil ? "Choose team folder…" : "Change team folder…") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Use for team"
            if panel.runModal() == .OK, let url = panel.url { catalog.choose(url) }
        }
    }
}

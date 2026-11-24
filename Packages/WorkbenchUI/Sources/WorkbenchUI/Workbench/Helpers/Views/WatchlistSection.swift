import SwiftUI
import WorkbenchCore

/// The companies a news machine follows: the Invested and passed deals, and the ones the investor adds. The investor
/// confirms an alias or a domain once, and matching uses it from then on.
struct WatchlistSection: View {
    let source: NewsSource
    let changed: () -> Void
    @State private var name = ""
    @State private var aliases = ""
    @State private var domain = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Companies you follow").textStyle(.headline)
            Text(
                "Deals you invested in or passed on are followed by themselves. A company is found in an article by its name, an alias you add, or its domain."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            if let problem { Text(problem).textStyle(.callout).foregroundStyle(Tone.bad.color) }
            ForEach(source.companies) { CompanyRow(company: $0, source: source, fail: fail, changed: changed) }
            HStack {
                TextField("Add a company", text: $name).frame(maxWidth: 200)
                TextField("Aliases, separated by commas", text: $aliases).frame(maxWidth: 240)
                TextField("Domain", text: $domain).frame(maxWidth: 160)
                Button("Add", action: add).disabled(name.cleaned == nil)
            }
        }
    }

    private func add() {
        attempt { try source.add(name: name, aliases: aliases, domain: domain) }
        name = ""
        aliases = ""
        domain = ""
    }

    private func fail(_ error: Error) { problem = "Could not save: \(error.localizedDescription)" }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
            problem = nil
            changed()
        } catch {
            fail(error)
        }
    }
}

/// One followed company, with its status and, opened, the aliases and domain.
private struct CompanyRow: View {
    let company: WatchedCompany
    let source: NewsSource
    let fail: (Error) -> Void
    let changed: () -> Void
    @State private var isOpen = false
    @State private var aliases = ""
    @State private var domain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Button(action: toggle) {
                    HStack(spacing: Space.s) {
                        Text(company.name)
                        Text(company.status == .passed ? "Passed" : "Portfolio").textStyle(.caption)
                            .padding(.horizontal, Space.s).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                        Text(detail).textStyle(.callout).foregroundStyle(.supporting)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Spacer()
                if !company.isDeal { Button("Remove", action: remove).buttonStyle(.borderless) }
            }
            if isOpen {
                HStack {
                    TextField("Aliases, separated by commas", text: $aliases).frame(maxWidth: 260)
                    TextField("Domain", text: $domain).frame(maxWidth: 180)
                    Button("Save", action: save)
                }
                .padding(.leading, Space.m)
            }
        }
    }

    private var detail: String {
        ([company.domain].compactMap { $0 } + company.aliases.map { "also \($0)" }).joined(separator: " · ")
    }

    private func toggle() {
        aliases = company.aliases.joined(separator: ", ")
        domain = company.domain ?? ""
        isOpen.toggle()
    }

    private func save() { act { try source.setDetails(of: company, aliases: aliases, domain: domain) } }
    private func remove() { act { try source.remove(company) } }

    private func act(_ work: () throws -> Void) {
        do {
            try work()
            isOpen = false
            changed()
        } catch {
            fail(error)
        }
    }
}

extension NewsSource {
    func chooser(for model: HelperModel) -> AnyView? { AnyView(NewsChooser(model: model)) }

    func pageSection(for model: HelperModel) -> AnyView? {
        AnyView(WatchlistSection(source: self, changed: model.reload))
    }
}

/// What a news machine needs before it can read: the web research switch, in plain words.
struct NewsChooser: View {
    let model: HelperModel
    @Environment(CaptureSettings.self) private var capture

    private var feedNames: String {
        let names = (model.machine.spec.feeds ?? []).map(\.name)
        return names.isEmpty ? "no news feed yet" : "the " + names.formatted(.list(type: .and)) + " news feeds"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(
                "\(model.name) fetches \(feedNames) and reads the articles that name a company you follow. Each check sends one plain request to each feed's site. It sends no company name and nothing about you. Articles are kept 30 days and deleted with the rest of your web data. It is off until you switch on web research."
            )
            .foregroundStyle(.supporting)
            Button("Turn on web research") {
                capture.set(.web, on: true)
                model.reload()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

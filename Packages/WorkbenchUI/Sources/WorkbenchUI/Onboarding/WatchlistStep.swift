import Foundation
import Observation
import SwiftUI
import WorkbenchCore

/// The companies a news machine follows, as the person sets them while setting up: ones they name, and the companies of
/// deals that stand in a won or a watch stage, found by what the stage means and never by its label.
@Observable
final class WatchlistModel {
    private(set) var followed: [WatchedCompany] = []
    /// Companies of won and watch deals the person has not pinned yet.
    private(set) var fromDeals: [WatchedCompany] = []
    private(set) var problem: String?

    @ObservationIgnored private let store: Store

    init(store: Store) {
        self.store = store
        refresh()
    }

    func refresh() {
        attempt("read the companies") {
            followed = try store.queries.watchedCompanies()
            let pinned = Set(try store.queries.watchEntries().compactMap(\.deal))
            let deals = WorkObject.fold(try store.queries.workEvents(), viewer: "").filter {
                $0.kind == "deal" && !$0.archived
            }
            fromDeals = WatchedCompany.inStages(of: deals).filter { !pinned.contains($0.id) }
        }
    }

    func follow(_ name: String, domain: String, status: WatchedCompany.Status) {
        attempt("follow the company") { try store.follow(name, domain: domain, status: status) }
        refresh()
    }

    func followDeals() {
        attempt("follow the deals") {
            try store.followDeals(
                WorkObject.fold(try store.queries.workEvents(), viewer: "").filter { $0.kind == "deal" && !$0.archived }
            )
        }
        refresh()
    }

    private func attempt(_ step: String, _ work: () throws -> Void) {
        do {
            try work()
            problem = nil
        } catch {
            problem = "Could not \(step): \(error.localizedDescription)"
        }
    }
}

struct WatchlistStep: View {
    @Environment(Crew.self) private var crew
    @State private var list: WatchlistModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let list { WatchlistBody(list: list) }
        }
        .task { list = WatchlistModel(store: crew.store) }
    }
}

private struct WatchlistBody: View {
    let list: WatchlistModel
    @State private var name = ""
    @State private var domain = ""
    @State private var status = WatchedCompany.Status.portfolio

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let problem = list.problem { ProblemBanner(text: problem) }
            ForEach(list.followed) { company in
                HStack {
                    Text(company.name)
                    Text(company.status == .passed ? "Passed on" : "Invested in").textStyle(.callout)
                        .foregroundStyle(.supporting)
                    if let domain = company.domain { Text(domain).textStyle(.callout).foregroundStyle(.supporting) }
                }
            }
            if !list.fromDeals.isEmpty {
                Button("Follow the \(list.fromDeals.count) companies in your deals") { list.followDeals() }
                    .buttonStyle(.ghost)
                Text(list.fromDeals.map(\.name).formatted(.list(type: .and))).textStyle(.callout)
                    .foregroundStyle(.supporting)
            }
            HStack {
                TextField("Company", text: $name).frame(maxWidth: 180)
                TextField("Web address, if you know it", text: $domain).frame(maxWidth: 200)
                Picker("", selection: $status) {
                    Text("Invested in").tag(WatchedCompany.Status.portfolio)
                    Text("Passed on").tag(WatchedCompany.Status.passed)
                }
                .labelsHidden().frame(maxWidth: 130)
                Button("Add") {
                    list.follow(name, domain: domain, status: status)
                    name = ""
                    domain = ""
                }
                .disabled(name.cleaned == nil)
            }
        }
    }
}

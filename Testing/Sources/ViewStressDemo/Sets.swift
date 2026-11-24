import Foundation

@testable import WorkbenchCore

/// The three invented data sets and the forms each is drawn in.
enum Sets {
    static let team = ExpressionSet(
        name: "team", spec: .team, facts: InventedTeam.facts(),
        candidates: { items, lens in
            [
                Candidate(name: "A-attention", views: FirstForm.views(of: lens.spec)),
                Candidate(
                    name: "A-attention-unfolded", views: FirstForm.views(of: lens.spec),
                    unfoldFirst: true),
                Candidate(
                    name: "B-by-kind",
                    views: [FactsView(title: "By kind", groupBy: "kind", layout: .list, order: .urgent)]),
                Candidate(
                    name: "C-people-table",
                    views: [
                        FactsView(title: "People", groupBy: "person", layout: .table, countBy: "kind", order: .urgent)
                    ]),
                Candidate(
                    name: "C-people-table-unfolded",
                    views: [
                        FactsView(title: "People", groupBy: "person", layout: .table, countBy: "kind", order: .urgent)
                    ],
                    unfoldFirst: true),
                Candidate(name: "D-board", views: [FactsView(title: "Entries", groupBy: "person", layout: .board)]),
                Candidate(
                    name: "E-by-project",
                    views: [
                        FactsView(
                            title: "By project", groupBy: "project", layout: .list, countBy: "person", order: .urgent)
                    ]),
            ]
        },
        summaries: InventedTeam.summaries)

    static let deals = ExpressionSet(
        name: "deals", spec: .dealIntake, facts: InventedDeals.facts(),
        candidates: { items, lens in
            [
                Candidate(
                    name: "default",
                    views: GalleryTemplate.dealIntake.startFactsView(of: lens.spec).map { [$0] } ?? []),
                Candidate(
                    name: "table-by-rating",
                    views: [
                        FactsView(
                            title: "Deals", groupBy: "rating", layout: .table, columns: ["company", "sector", "stage"])
                    ]),
                Candidate(
                    name: "board-by-stage", views: [FactsView(title: "Pipeline", groupBy: "stage", layout: .board)]),
                Candidate(name: "derived", views: FirstForm.views(of: lens.spec)),
            ]
        })

    static let news = ExpressionSet(
        name: "news", spec: .newsSignals, facts: InventedNews.facts(),
        candidates: { items, lens in
            [
                Candidate(
                    name: "default",
                    views: GalleryTemplate.newsSignals.startFactsView(of: lens.spec).map { [$0] } ?? []),
                Candidate(name: "derived", views: FirstForm.views(of: lens.spec)),
                Candidate(
                    name: "by-polarity",
                    views: [FactsView(title: "Signals", groupBy: "polarity", layout: .list, order: .urgent)]),
            ]
        })
}

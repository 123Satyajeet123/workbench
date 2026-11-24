import Foundation

/// Twelve invented startups from a deal machine: a sector, a stage, who sent it, and a rating of three levels that the
/// criteria gave. The names are invented and end in "Example".
enum InventedDeals {
    private static let rows: [(company: String, sector: String, stage: String, from: String, rating: String)] = [
        ("Northwind Grid Example", "grid software for small utilities", "seed", "Warden Example", "hot"),
        ("Plover Freight Example", "freight booking for river barges", "pre-seed", "Warden Example", "warm"),
        ("Quillfeather Example", "legal drafting tools", "series A", "Tamsin Example", "hot"),
        ("Ostrava Cold Chain Example", "cold storage sensors", "seed", "Ines Example", "warm"),
        ("Brindle Health Example", "clinic scheduling", "pre-seed", "Tamsin Example", "cold"),
        ("Marlow Robotics Example", "warehouse picking arms", "series A", "Warden Example", "hot"),
        ("Tallis Pay Example", "payroll for seasonal crews", "seed", "Jomo Example", "warm"),
        ("Verdant Ledger Example", "carbon accounting for farms", "pre-seed", "Ines Example", "cold"),
        ("Kestrel Learning Example", "adult language lessons", "later", "Tamsin Example", "cold"),
        ("Harrow Mapping Example", "indoor maps for hospitals", "seed", "Jomo Example", "warm"),
        ("Lumen Fold Example", "foldable solar panels", "unknown", "Warden Example", "cold"),
        (
            "Cobalt Kitchen Example",
            "shared kitchens for caterers with a very long pitch line that goes on to say what the product does",
            "pre-seed", "Ines Example", "warm"
        ),
    ]

    static func facts() -> [InventedFact] {
        rows.enumerated().map { index, row in
            InventedFact(
                quote:
                    "\(row.company) raises a \(row.stage) round for \(row.sector) and asks for a call; the deck is attached.",
                fields: [
                    "company": row.company, "sector": row.sector, "stage": row.stage, "from": row.from,
                    "rating": row.rating,
                ], daysAgo: index % 5)
        }
    }
}

/// Seventeen invented events about six followed companies: what happened, whether it is good or bad news for the
/// company, and the day it happened.
enum InventedNews {
    private static let rows: [(company: String, event: String, polarity: String, words: String)] = [
        ("Aldermoor Example", "funding", "positive", "has raised a new round led by a fund that backed it before."),
        ("Aldermoor Example", "hiring", "positive", "named a new head of sales who comes from a larger rival."),
        ("Birchfield Example", "layoff", "negative", "says it will cut forty roles across two sites this quarter."),
        (
            "Birchfield Example", "exec exit", "negative",
            "lost its technical founder, who leaves at the end of the month."
        ),
        ("Birchfield Example", "lawsuit", "negative", "was sued by a supplier over late payments on three invoices."),
        ("Cinder Bay Example", "product", "positive", "launched a cheaper plan aimed at very small teams."),
        (
            "Cinder Bay Example", "regulatory", "neutral",
            "received a notice that asks for more detail on its data storage."
        ),
        ("Dunmore Example", "acquisition", "positive", "agreed to buy a small rival and will keep its whole team."),
        ("Dunmore Example", "product", "neutral", "changed the name of its main app and kept every feature."),
        ("Elmstead Example", "shutdown", "negative", "will close its older product line by the end of the year."),
        (
            "Elmstead Example", "funding", "neutral",
            "is said to be in early talks about a round, but nothing is signed."
        ),
        ("Fenwick Example", "hiring", "positive", "opened twenty roles in its new office and named two directors."),
        ("Fenwick Example", "regulatory", "positive", "won a licence it had waited for since last spring."),
        (
            "Fenwick Example", "lawsuit", "neutral",
            "settled an old case and paid a small sum, with no change to the business."
        ),
        (
            "Aldermoor Example", "product", "neutral",
            "published a long roadmap post with dates for the next three releases."
        ),
        (
            "Cinder Bay Example", "layoff", "negative",
            "is reported to have let go of its whole support team in one call."
        ),
        ("Dunmore Example", "funding", "positive", "closed a bridge round to cover the cost of the new purchase."),
    ]

    static func facts() -> [InventedFact] {
        rows.enumerated().map { index, row in
            InventedFact(
                quote: "\(row.company) \(row.words)",
                fields: [
                    "company": row.company, "event": row.event, "polarity": row.polarity,
                    "date": "2026-11-\(String(format: "%02d", 25 - index % 12))",
                    "headline": "\(row.company) \(row.words)",
                    "feed": "Example Wire",
                ], daysAgo: index % 5)
        }
    }
}

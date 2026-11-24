import Foundation

extension HelperSpec {
    /// VC pack: startups found on the web that fit the investor's criteria. One model call reads one page and lists
    /// the startups it names, each with a quote and the numbers and judgments each rule needs. Code checks the quotes
    /// and the names, and makes the hot, warm or cold call by the same table as deal intake.
    public static let outbound = HelperSpec(
        task: Outbound.task, source: .webSearch,
        brief: """
            You read one web page for a venture investor who looks for new startups that fit their criteria. List \
            each startup the page names that the page says something about. A page may name many startups or none. \
            Use only what the page says about each one. A big company, a fund, an investor or a news outlet is not a \
            startup to list. Give the startup's own name, and its website domain only when the page writes it.
            """,
        fields: [
            Field("company", .text(required: true), meaning: "The startup's own name, as the page writes it."),
            Field(
                "domain", .text(required: false),
                meaning: "Its website domain as the page writes it, such as acme.com; empty when the page gives none."),
            Field("sector", .text(required: false), meaning: "What it does, in a few words; empty when not said."),
            Field(
                "rating", .computed(["hot", "warm", "cold"]),
                meaning: "Hot, warm or cold, from the criteria, by the table."),
        ],
        citation: .one, view: .grouped(by: "rating"), title: "company", badges: ["rating", "sector"],
        tones: ["hot": .good, "warm": .neutral, "cold": .bad], itemsNoun: "startups", nudge: nil,
        criteria: .starter)
}

/// The names and limits of the outbound search.
public enum Outbound {
    /// The template's task. A machine made from it has its own task, this one and a dash and a suffix.
    public static let task = "vc.outbound"
    public static let queryTask = "vc.outbound.queries"
    /// Fields code adds to what the model gave: the page address and the day it was fetched.
    public static let urlField = "url"
    public static let fetchedField = "fetched"
    /// The number of a page's line: each page is one model call with one line.
    public static let pageLine: Int64 = 1
}

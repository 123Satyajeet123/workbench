import Foundation

extension HelperSpec {
    /// VC pack: typed facts from news about the companies the investor follows. One model call reads one article. The
    /// model chooses the event, the polarity and the date; code checks the company, the quote and the date.
    public static let newsSignals = HelperSpec(
        task: NewsSignals.task, source: .news,
        brief: """
            You read one news article for a venture investor. They follow some companies: their portfolio and deals \
            they passed on. The Companies list names those the article may be about. For each of them that the \
            article reports something about, give one item for each distinct event. An article that names a company \
            only in passing, or says nothing new about it, gives no item. Use only what the article says. Event: the \
            kind of thing that happened. Polarity: whether it is good news, bad news or neither for the company, as \
            an investor in it would see it. Date: when the event happened or was announced, as YYYY-MM-DD, empty when \
            the article does not say; never guess. The quote is at most 25 words.
            """,
        fields: [
            Field(
                "company", .member(of: NewsSignals.companies),
                meaning: "The company the event is about. Two companies can share a name: choose the one meant."),
            Field(
                "event", .choice(NewsSignals.events),
                meaning:
                    "funding: a round raised or announced. layoff: staff cut. exec exit: a founder or senior leader leaves. shutdown: the company closes or stops a main product. lawsuit: a legal case. regulatory: a ruling, notice or licence from an authority. product: a launch or a major change. hiring: a notable hire or a hiring drive. acquisition: the company buys, or is bought."
            ),
            Field(
                "polarity", .choice(["positive", "negative", "neutral"]),
                meaning: "Good, bad or neither for the company, as an investor in it would see it."),
            Field(
                "date", .text(required: false), meaning: "When the event happened, as YYYY-MM-DD; empty when not said."),
        ],
        citation: .one, view: .board(groupBy: "company", expected: NewsSignals.companies), title: "headline",
        badges: ["event", "feed", "date"], tones: ["positive": .good, "negative": .bad, "neutral": .neutral],
        itemsNoun: "signals", nudge: nil)
}

/// The names a news signal is made of.
public enum NewsSignals {
    /// The template's task. A machine made from it has its own task, this one and a dash and a suffix, and its items
    /// are its own; Today and the deals read the items of every such machine.
    public static let task = "vc.news-signals"

    /// Whether `task` is the template's or a machine's made from it. The task of a trial is not.
    public static func owns(_ task: String) -> Bool {
        task == Self.task || (task.hasPrefix(Self.task + "-") && !Trial.isTrial(task))
    }

    static let ownTasks = "(task = ? OR (task LIKE ? AND task NOT LIKE '%#trial'))"
    static let ownTasksArguments: [String] = [task, task + "-%"]
    /// The context set of followed companies the model chooses from.
    public static let companies = "companies"
    public static let events = [
        "funding", "layoff", "exec exit", "shutdown", "lawsuit", "regulatory", "product", "hiring", "acquisition",
    ]
    /// The most words a quote may have.
    public static let quoteWords = 25
    /// The characters of an article the model reads, and a quote may come from.
    public static let articleBudget = 12_000

    /// Fields code adds to what the model gave: the company's id, the article's address and headline, its feed and
    /// whether the feed is trusted.
    public static let idField = "company_id"
    public static let urlField = "url"
    public static let feedField = "feed"
    public static let trustedField = "trusted"
    public static let headlineField = "headline"
}

extension Item {
    /// A negative signal from a trusted feed: what Today lists as information.
    public var isTrustedBadNews: Bool {
        NewsSignals.owns(task) && self["polarity"] == "negative" && self[NewsSignals.trustedField] == "yes"
    }

    /// The deal or hand-added company a news signal is about.
    public var signalCompany: String { self[NewsSignals.idField] }
    public var signalURL: URL? { URL(string: self[NewsSignals.urlField]) }
}

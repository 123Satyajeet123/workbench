import Foundation
import Observation
import WorkbenchCore

/// What the proof place of the inspector shows.
enum ProofContent: Equatable {
    /// Placeholder rows of the height the lines will have.
    case loading(rows: Int)
    case lines([ProofEntry])
    /// The fact cites no chat line, so its quote stands alone.
    case quote(String)
    case notice(String)
    case problem(String)
}

/// Everything the inspector writes about one fact, as plain values.
struct InspectorCard: Equatable {
    var headline: FactHeadline
    var meta: String
    var source: String
    var proof: ProofContent
    var history: [String]
}

/// Loads the proof of one fact at a time: the chat lines around what it cites, read as the Today list reads them, and
/// the history the store keeps. A line is read again only when the fact cites other lines; a changed mark or due date
/// reads the history alone.
@Observable
final class ProofModel {
    enum Phase: Equatable {
        case idle, loading, ready, quoteOnly, missing
        case failed(String)
    }

    /// The lines the machine's run read, as `TodayModel.chatLines` gives them.
    private(set) var lines: [ChatLine] = []
    private(set) var phase = Phase.idle

    /// How many lines around a cited line the proof shows.
    static let reach = 2
    /// The most placeholder rows: a fact that cites a long range shows its first lines.
    static let mostRows = 12

    private struct Key: Equatable {
        var id: Int64?
        var citeFirst: Int64
        var citeLast: Int64
        var run: RunID?
        var citesLine: Bool

        init(_ item: Item) {
            (id, citeFirst, citeLast, run) = (item.id, item.citeFirst, item.citeLast, item.run)
            citesLine = ProofModel.cites(item)
        }
    }

    private struct Known {
        var key: Key
        var history: ProofHistory
    }

    @ObservationIgnored private let titleOf: (Item) -> String
    @ObservationIgnored private let readLines: (Item) async throws -> [ChatLine]
    @ObservationIgnored private let crew: Crew
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let locale: Locale
    private var known: Known?

    init(
        crew: Crew, store: Store, locale: Locale = .current, title: @escaping (Item) -> String,
        lines: @escaping (Item) async throws -> [ChatLine]
    ) {
        self.crew = crew
        self.store = store
        self.locale = locale
        titleOf = title
        readLines = lines
    }

    /// A model that reads its lines and titles as the Today list does.
    convenience init(today: TodayModel, crew: Crew, store: Store, locale: Locale = .current) {
        self.init(
            crew: crew, store: store, locale: locale, title: today.title(of:),
            lines: { try await today.chatLines(around: $0, reach: Self.reach) })
    }

    static func cites(_ item: Item) -> Bool { item.citeFirst > 0 && item.source != .web }

    /// The rows a proof of `item` has when its lines are all one line long.
    static func placeholderRows(for item: Item) -> Int {
        min(Int(item.citeLast - item.citeFirst) + 1 + 2 * reach, mostRows)
    }

    func helper(of item: Item) -> HelperModel? { crew.machines.first { $0.spec.task == item.task } }

    func load(_ item: Item) async {
        let key = Key(item)
        let history = readHistory(of: item)
        guard known?.key != key || phase == .loading || phase.isFailure else {
            known?.history = history
            return
        }
        known = Known(key: key, history: history)
        lines = []
        guard Self.cites(item) else {
            phase = .quoteOnly
            return
        }
        phase = .loading
        do {
            let found = try await readLines(item)
            guard known?.key == key else { return }
            lines = found
            phase = found.isEmpty ? .missing : .ready
        } catch {
            guard !Task.isCancelled, known?.key == key else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    func clear() {
        known = nil
        lines = []
        phase = .idle
    }

    func card(for item: Item) -> InspectorCard {
        let words = DateWords(now: store.clock(), locale: locale)
        let helper = helper(of: item)
        let chat = (helper?.source as? WhatsAppSource)?.chats.first { $0.jid == item.scope }?.name
        return InspectorCard(
            headline: FactHeadline(item: item, title: titleOf(item)),
            meta: InspectorWords.meta(of: item, words),
            source: InspectorWords.source(of: item, chat: chat, words), proof: content(for: item, words),
            history: known?.key == Key(item) ? (known?.history.sentences(of: item, words) ?? []) : [])
    }

    private func content(for item: Item, _ words: DateWords) -> ProofContent {
        guard known?.key == Key(item) else { return .loading(rows: Self.placeholderRows(for: item)) }
        switch phase {
        case .idle, .loading: return .loading(rows: Self.placeholderRows(for: item))
        case .ready: return .lines(ProofEntry.lines(lines, of: item, words))
        case .quoteOnly: return .quote(item.quote)
        case .missing: return .notice(item.isSourceDeleted ? InspectorWords.deleted : InspectorWords.notFound)
        case .failed(let reason): return .problem(InspectorWords.unreadable(reason))
        }
    }

    private func readHistory(of item: Item) -> ProofHistory {
        guard let id = item.id else { return ProofHistory() }
        let queries = store.queries
        let run = item.run.flatMap { id in (try? queries.runs(since: item.day.start))?.first { $0.id == id } }
        let version = run.flatMap { run in
            (try? queries.prompts(task: item.task))?.first { $0.hash == run.prompt }?.number
        }
        return ProofHistory(
            machine: helper(of: item)?.name, version: version, found: run?.startedAt,
            marks: (try? queries.marks(ofItem: id)) ?? [])
    }
}

extension ProofModel.Phase {
    fileprivate var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

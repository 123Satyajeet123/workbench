import Foundation

/// The name of one block a machine put on a page. It is made when the block is made and never used again.
public struct MachineBlockID: Hashable, Sendable {
    public let rawValue: String

    public init() { rawValue = UUID().uuidString }

    /// The name of a block as the store kept it; nil for an empty one.
    public init?(_ rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }
}

/// One block of a page, in the page's order: a paragraph the person wrote, or a block of a machine.
public enum PageBlockRef: Hashable, Sendable {
    case note(BlockID)
    case machine(MachineBlockID)
}

/// A view over a machine's facts. It holds no words: its rows are the fact records, with their quotes and marks.
public struct FactsView: Equatable, Sendable {
    public enum Layout: String, CaseIterable, Sendable {
        case list, board, table, counts
    }

    public var title: String
    /// The values a fact's field may have to be shown, by field. A field that is not named shows every value.
    public var filters: [String: [String]]
    /// The field whose values make the sections; nil for one section.
    public var groupBy: String?
    public var layout: Layout
    /// The fields a table shows, in order.
    public var columns: [String]

    public init(
        title: String, filters: [String: [String]] = [:], groupBy: String? = nil, layout: Layout = .table,
        columns: [String] = []
    ) {
        self.title = title
        self.filters = filters
        self.groupBy = groupBy
        self.layout = layout
        self.columns = columns
    }
}

/// What a machine's words rest on. Each names one line of evidence, so an erase of that line finds the words.
public enum PageCite: Hashable, Sendable {
    /// A fact, by its id: the line and span of its quote.
    case fact(Int64)
    /// A paragraph the person wrote on the page.
    case note(BlockID)
    /// What the person typed when they asked for this change.
    case request
}

/// Sentences a model wrote, with what they rest on.
public struct CitedText: Equatable, Sendable {
    public var text: String
    public var cites: [PageCite]

    public init(text: String, cites: [PageCite]) {
        self.text = text
        self.cites = cites
    }
}

/// A small spreadsheet: a header and rows of the same length. A cell is words, a number, or a formula. Its cells
/// come from somewhere, so it names what they rest on, as text does.
public struct Grid: Equatable, Sendable {
    public var title: String
    public var columns: [String]
    public var rows: [[String]]
    public var cites: [PageCite]

    public init(title: String, columns: [String], rows: [[String]], cites: [PageCite]) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.cites = cites
    }
}

/// What a picker block asks the person to choose. The choice itself is a grant in the capture policy, never a part
/// of the block: a block on a page grants nothing.
public enum PickerKind: String, CaseIterable, Sendable {
    case whatsappChats = "whatsapp_chats"
    case mailLabel = "mail_label"
    case sites
    case files
}

public enum MachineBlock: Equatable, Sendable {
    case heading(String)
    case text(CitedText)
    case facts(FactsView)
    case grid(Grid)
    case picker(PickerKind)
}

/// A page as its blocks: the order of all of them, and what each machine block is. The person's paragraphs live in
/// the note; the page names them.
public struct MachinePage: Equatable, Sendable {
    public var order: [PageBlockRef]
    public var blocks: [MachineBlockID: MachineBlock]

    public init(order: [PageBlockRef] = [], blocks: [MachineBlockID: MachineBlock] = [:]) {
        self.order = order
        self.blocks = blocks
    }
}

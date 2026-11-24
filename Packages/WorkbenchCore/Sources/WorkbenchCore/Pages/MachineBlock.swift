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

    /// Which facts the view holds, by what the spec says about them.
    public enum Show: String, CaseIterable, Sendable {
        /// Every fact that passes the filters.
        case all
        /// The facts that are still open in the machine's lifecycle.
        case open
        /// The open facts that ask the person for something, are late, or are in trouble.
        case needsAttention
    }

    /// The order of the facts in a section, and of the sections.
    public enum Order: String, CaseIterable, Sendable {
        /// As the store gives them.
        case stored
        /// What needs the person first, then what is open and due soonest, then the newest.
        case urgent
    }

    public var title: String
    /// The values a fact's field may have to be shown, by field. A field that is not named shows every value.
    public var filters: [String: [String]]
    /// The field whose values make the sections; nil for one section.
    public var groupBy: String?
    public var layout: Layout
    /// The fields a table shows, in order.
    public var columns: [String]
    /// With a grouping: each section folds into one row that counts its facts by the values of this field, and the
    /// row unfolds to its facts. Nil shows every fact of every section.
    public var countBy: String?
    public var show: Show
    public var order: Order
    /// How many facts of each section show before the rest fold behind one control; nil shows them all.
    public var limit: Int?

    public init(
        title: String, filters: [String: [String]] = [:], groupBy: String? = nil, layout: Layout = .table,
        columns: [String] = [], countBy: String? = nil, show: Show = .all, order: Order = .stored,
        limit: Int? = nil
    ) {
        self.title = title
        self.filters = filters
        self.groupBy = groupBy
        self.layout = layout
        self.columns = columns
        self.countBy = countBy
        self.show = show
        self.order = order
        self.limit = limit
    }

    /// The title of a view that is just grouped by a field, as `FirstForm` gives it.
    public static func title(groupedBy field: String) -> String { "By \(field)" }

    /// The forms a person can switch a view among. A form is a layout with the settings it needs.
    public enum Form: String, CaseIterable, Sendable {
        case foldedList, list, table, board, counts
    }

    /// The form the view is in now.
    public var form: Form {
        switch layout {
        case .list: countBy == nil ? .list : .foldedList
        case .table: .table
        case .board: .board
        case .counts: .counts
        }
    }

    /// The view as the person would have it in `form`, grouped by `field`; everything else stays. Nil when the form
    /// needs sections and there is no field to make them. `countField` is what a folded list counts by.
    public func changed(to form: Form, groupBy field: String?, countField: String?) -> FactsView? {
        var view = self
        if let old = groupBy, let field, title == Self.title(groupedBy: old) {
            view.title = Self.title(groupedBy: field)
        }
        view.groupBy = field
        view.countBy = nil
        switch form {
        case .foldedList:
            guard field != nil, let countField, countField != field else { return nil }
            view.layout = .list
            view.countBy = countField
        case .list: view.layout = .list
        case .table: view.layout = .table
        case .board:
            guard field != nil else { return nil }
            view.layout = .board
        case .counts: view.layout = .counts
        }
        return view
    }

    /// The columns a table shows: the ones named, without the field the sections are made of, which the heading of
    /// each section already says.
    public var shownColumns: [String] {
        let named = columns.isEmpty ? [PageCatalog.quoteColumn] : columns
        return named.filter { $0 != groupBy }
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

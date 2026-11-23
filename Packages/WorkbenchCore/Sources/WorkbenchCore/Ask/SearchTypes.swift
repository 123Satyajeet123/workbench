import Foundation
import Kernel
import Lines

/// Who reads, and which run the reading belongs to. Every line a tool returns is kept in the window of this run.
public struct ToolContext: Sendable {
    public let run: RunID
    public let reader: PersonID

    public init(run: RunID, reader: PersonID) {
        self.run = run
        self.reader = reader
    }
}

public struct FactFilter: Sendable, Equatable {
    /// Only facts of these machines.
    public var tasks: [String]?
    /// Only facts that are not closed, withdrawn, replaced or rejected.
    public var openOnly: Bool
    /// Facts whose time starts in `since..<until`.
    public var since: Date?
    public var until: Date?

    public init(tasks: [String]? = nil, openOnly: Bool = false, since: Date? = nil, until: Date? = nil) {
        self.tasks = tasks
        self.openOnly = openOnly
        self.since = since
        self.until = until
    }
}

public struct LineFilter: Sendable, Equatable {
    public var sources: Set<SourceKind>?
    /// Lines sent in `since..<until`.
    public var since: Date?
    public var until: Date?

    public init(sources: Set<SourceKind>? = nil, since: Date? = nil, until: Date? = nil) {
        self.sources = sources
        self.since = since
        self.until = until
    }
}

/// A line a tool returned. `number` is its place in the window of the run: the number the model cites.
public struct FoundLine: Sendable, Equatable {
    public let number: Int
    public let lineID: LineID
    public let text: String
    public let source: SourceKind
    public let who: String?
    public let eventTime: Date?
}

/// A fact a tool returned, with the lines it cites. `state` is `open`, or the outcome that ended it.
public struct FoundFact: Sendable, Equatable {
    public let item: Int64
    public let task: String
    public let title: String
    public let fields: [String: String]
    public let state: String
    public let cites: [FoundLine]
}

/// A work object a tool opened: what it is, what stands below it, and the facts filed in it.
public struct FoundObject: Sendable, Equatable {
    public struct Child: Sendable, Equatable {
        public let id: WorkObjectID
        public let type: TypeID
        public let name: String
    }

    public let id: WorkObjectID
    public let type: TypeID
    public let name: String
    /// The labels of its current stages; empty when its type has no stages.
    public let stages: [String]
    public let archived: Bool
    public let children: [Child]
    public let facts: [FoundFact]
}

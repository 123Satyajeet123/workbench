import Foundation

/// Everything the read-only page tools may tell a model, written to one file by the eval before a call. The handles
/// (F1, B1, …) are the ones the composer gives, so a name a tool returns resolves the same way in both arms.
public struct PageToolFixture: Codable, Sendable, Equatable {
    public struct Field: Codable, Sendable, Equatable {
        public var name: String
        public var value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public struct Fact: Codable, Sendable, Equatable {
        public var handle: String
        public var day: String
        public var quote: String
        /// The fields of the machine's spec in order, the ones code computes among them.
        public var fields: [Field]

        public init(handle: String, day: String, quote: String, fields: [Field]) {
            self.handle = handle
            self.day = day
            self.quote = quote
            self.fields = fields
        }

        /// The value of a field of the spec, or the day.
        func value(of name: String) -> String? {
            name == Self.dayName ? day : fields.first { $0.name == name }?.value
        }

        static let dayName = "day"
        static let quoteName = "quote"
    }

    public struct CatalogEntry: Codable, Sendable, Equatable {
        public var field: String
        public var values: [String]

        public init(field: String, values: [String]) {
            self.field = field
            self.values = values
        }
    }

    public var facts: [Fact]
    public var catalog: [CatalogEntry]
    public var columns: [String]
    /// The blocks of the page in order, each as the composer shows it: `B1 person: …` or `B2 machine: …`.
    public var blocks: [String]
    public var machineBlockCount: Int
    public var blockCap: Int

    public init(
        facts: [Fact], catalog: [CatalogEntry], columns: [String], blocks: [String], machineBlockCount: Int,
        blockCap: Int
    ) {
        self.facts = facts
        self.catalog = catalog
        self.columns = columns
        self.blocks = blocks
        self.machineBlockCount = machineBlockCount
        self.blockCap = blockCap
    }
}

/// One line of the server's own log: a tool call, how big its answer was, and the handles the answer named.
public struct PageToolLogEntry: Codable, Sendable, Equatable {
    public var tool: String
    public var arguments: String
    public var resultBytes: Int
    public var isError: Bool
    /// The call was above the cap and was refused.
    public var refused: Bool
    public var returnedHandles: [String]

    public init(
        tool: String, arguments: String, resultBytes: Int, isError: Bool, refused: Bool, returnedHandles: [String]
    ) {
        self.tool = tool
        self.arguments = arguments
        self.resultBytes = resultBytes
        self.isError = isError
        self.refused = refused
        self.returnedHandles = returnedHandles
    }
}

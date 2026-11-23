import Foundation

/// Where a claim's support is: a stored evidence line, or a page snapshot. A cite names the words it relies on; code
/// finds them in the stored text and never trusts the name alone.
public struct Cite: Codable, Sendable, Equatable {
    public enum Source: Codable, Sendable, Equatable, Hashable {
        /// The id of a stored evidence line.
        case line(Data)
        /// The row of a page snapshot.
        case page(snapshot: Int64)
    }

    public var source: Source
    public var quote: String

    public init(source: Source, quote: String) {
        self.source = source
        self.quote = quote
    }
}

/// One thing a work product says that can be checked, and what it rests on.
public struct ProductClaim: Codable, Sendable, Equatable {
    public var text: String
    public var cites: [Cite]

    public init(text: String, cites: [Cite]) {
        self.text = text
        self.cites = cites
    }
}

/// The output of one task: a list of claims with cites. The judge takes any product, whoever wrote it.
public struct WorkProduct: Sendable, Equatable {
    /// The task type, such as `research`. A rubric and a rung belong to one.
    public var taskType: String
    /// The work object of the deal the product is about.
    public var object: WorkObjectID
    /// Who the claims are about. Its name needs no cite inside a claim.
    public var subject: String
    /// What the note was asked to answer.
    public var question: String
    /// The whole note as the person reads it. The writer's name is not part of it.
    public var text: String
    public var claims: [ProductClaim]

    public init(
        taskType: String, object: WorkObjectID, subject: String, question: String, text: String, claims: [ProductClaim]
    ) {
        self.taskType = taskType
        self.object = object
        self.subject = subject
        self.question = question
        self.text = text
        self.claims = claims
    }

    public static let researchTask = "research"
}

/// The text a cite points to, as the store holds it.
public struct SourceText: Sendable, Equatable {
    public enum Origin: Sendable, Equatable {
        case line
        case page(url: URL, fetchedAt: Date, contentHash: String, pageDate: Date?)
    }

    public var source: Cite.Source
    public var text: String
    public var origin: Origin

    public init(source: Cite.Source, text: String, origin: Origin) {
        self.source = source
        self.text = text
        self.origin = origin
    }
}

/// Where the judge finds the text a cite names. The store is the one library; a test or a probe holds its own.
public protocol CiteLibrary: Sendable {
    /// Nil when the line or snapshot is not stored (erased, or never kept).
    func text(of source: Cite.Source) throws -> SourceText?
}

/// A library over a fixed list, for a probe that holds its pages in memory.
public struct FixedCiteLibrary: CiteLibrary {
    private let texts: [Cite.Source: SourceText]

    public init(_ texts: [SourceText]) {
        self.texts = Dictionary(texts.map { ($0.source, $0) }) { first, _ in first }
    }

    public func text(of source: Cite.Source) throws -> SourceText? { texts[source] }
}

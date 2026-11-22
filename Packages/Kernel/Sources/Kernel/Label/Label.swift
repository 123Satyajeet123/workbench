// Source: built (research K5 §2.2). Join rule as in qm src/memory/facts.ts:49-60 (union of sources) and agentes-chat
// packages/engine/src/context/items.ts:502 (union of channels).

/// Who may read a thing, stated as where it came from: the sources it holds and the classes of its content.
/// Readers are not stored; `readers(grants:roster:)` computes them from the sources' grants at read time.
/// A label always holds at least one source.
public struct Label: Hashable, Sendable {
    public let sources: Set<SourceID>
    public let classes: Set<SourceClass>

    public init(source: SourceID, classes: Set<SourceClass> = []) {
        sources = [source]
        self.classes = classes
    }

    public init(sources: Set<SourceID>, classes: Set<SourceClass>) throws(LabelError) {
        guard !sources.isEmpty else { throw .noSources }
        self.sources = sources
        self.classes = classes
    }

    private init(unioning first: Label, _ second: Label) {
        sources = first.sources.union(second.sources)
        classes = first.classes.union(second.classes)
    }

    /// The label of anything made from both: every source and every class of either.
    public func joined(with other: Label) -> Label { Label(unioning: self, other) }

    /// The label of anything made from this and `others`, such as a model output over its whole input window.
    public func joined(with others: some Sequence<Label>) -> Label { others.reduce(self) { $0.joined(with: $1) } }
}

public enum LabelError: Error, Equatable, Sendable {
    /// The label had no source.
    case noSources
}

import Kernel
import PropertyBased

/// A small universe for label properties: five people, six sources, three classes. Each source has one owner, so
/// random grant lists are owner-signed unless a test breaks them on purpose. Small sets make overlaps likely, which
/// is where label bugs show.
enum LabelWorld {
    static let people = (0..<5).map { person("p\($0)") }
    static let sourceValues = (0..<6).map { source(people[$0 % 5], "s\($0)") }
    static let sources = sourceValues.map(\.id)
    static let classes = (0..<3).map { sourceClass("c\($0)") }

    static func sourceValue(of id: SourceID) -> Source { sourceValues.first { $0.id == id } ?? sourceValues[0] }
    static func owner(of id: SourceID) -> PersonID { sourceValue(of: id).owner }
    static func owned(by signer: PersonID) -> SourceID { sourceValues.first { $0.owner == signer }?.id ?? sources[0] }

    static let readerSet = pick(people).set(ofAtMost: 0...5)

    static let label = zip(pick(sources), pick(sources).set(ofAtMost: 0...3), pick(classes).set(ofAtMost: 0...2))
        .map { first, more, classes in
            Label(source: first, classes: classes).joined(with: more.map { Label(source: $0) })
        }

    static let roster = pick(people).set(ofAtMost: 2...5).map(Roster.init(members:))

    /// For each source: no grant (about one in seven), one grant at epoch 0, or that grant and a later one.
    static let grants = zip(Gen.bool(0.85), readerSet, readerSet.optional(valueRate: 0.3)).array(of: sources.count)
        .map { rows in
            zip(sourceValues, rows).flatMap { source, row -> [Grant] in
                let (present, readers, newer) = row
                guard present else { return [] }
                let first = Grant(signer: source.owner, source: source, readers: readers, epoch: 0)
                guard let newer else { return [first] }
                return [first, Grant(signer: source.owner, source: source, readers: newer, epoch: 1)]
            }
        }

    /// Grants for random sources, each signed by someone who does not own the source, at any epoch.
    static let strangerGrants = zip(pick(sourceValues), pick(people), readerSet, Gen.uint64(in: 0...5))
        .compactMap { source, signer, readers, epoch in
            signer == source.owner ? nil : Grant(signer: signer, source: source, readers: readers, epoch: epoch)
        }
        .array(of: 1...4)

    /// A label that holds a part the signer owns, and the signer's release of one of its sources: mostly into a
    /// source the signer owns, sometimes into any source. This covers the multi-owner summary, where one owner must
    /// not open another owner's part, and releases into a source someone else controls.
    static let summaryAndRelease = zip(label, pick(people), Gen.int(in: 0...5), Gen.bool(0.7), pick(sources))
        .map { label, signer, choice, intoOwn, anySource in
            let owned = owned(by: signer)
            let summary = label.joined(with: Label(source: owned))
            let covers = summary.sources.sorted()[choice % summary.sources.count]
            return (summary, Release(signer: signer, covers: covers, to: intoOwn ? owned : anySource))
        }

    /// One model call: the labels of every line in its window, and what the model said about them.
    static let extraction = zip(
        label.array(of: 1...5), Gen.int(in: 0...4).set(ofAtMost: 0...4), pick(["commitment", "decision", "risk"])
    ).map { window, cited, kind in
        Extraction(window: window, output: ModelOutput(cited: cited.filter { $0 < window.count }, kind: kind))
    }
}

struct ModelOutput: Sendable {
    var cited: Set<Int>
    var kind: String
}

struct Extraction: Sendable {
    var window: [Label]
    var output: ModelOutput
}

/// A generator of one of `values`, which must not be empty. It shrinks toward the first value.
func pick<Value: Sendable>(_ values: [Value]) -> Generator<Value, Shrink.Integer<Int>> {
    Gen.int(in: 0...(values.count - 1)).map { values[$0] }
}

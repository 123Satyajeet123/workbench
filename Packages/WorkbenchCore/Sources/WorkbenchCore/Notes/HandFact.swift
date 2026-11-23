import Foundation
import GRDB
import Kernel

/// A fact the person adds by hand, in the fields of a fact machine.
public struct HandFact: Sendable, Equatable {
    public var kind: String
    public var text: String
    public var person: String
    public var project: String
    public var due: WorkDay?

    public init(kind: String, text: String, person: String = "", project: String = "", due: WorkDay? = nil) {
        self.kind = kind
        self.text = text
        self.person = person
        self.project = project
        self.due = due
    }
}

extension HelperSpec {
    /// The kinds a fact of this machine may have, in the machine's own order.
    public var factKinds: [String] { fields.first { $0.name == "kind" }?.kind.fixedValues ?? [] }

    /// Whether a person can add a fact by hand to this machine: it has kinds and a field that holds the words.
    public var takesHandFacts: Bool { !factKinds.isEmpty && fields.contains { $0.name == title } }
}

extension Store {
    /// Adds a fact the person typed: no model run, and the machine's lifecycle and timers as for any fact. Its words are
    /// one typed line of evidence in the machine's container, and the fact quotes that line whole, so it rests on a line
    /// as a model's fact does and is erased with it. The line and the fact commit together, through the one writer of
    /// evidence and the one insert of items. Returns nil when the words or the kind do not fit the machine.
    @discardableResult
    public func addFact(_ fact: HandFact, to spec: HelperSpec = .team, owner: PersonID) throws -> Int64? {
        guard spec.takesHandFacts, spec.factKinds.contains(fact.kind), let words = fact.text.cleaned else { return nil }
        return try recordTypedWords(words, label: "fact", container: spec.task, owner: owner) { line, db in
            let id = try Self.insertItem(db, try handItem(fact, words: words, of: spec, quoting: line), at: clock())
            if spec.lifecycle != nil { try reconcileTimers(db, item: id) }
            return id
        }
    }

    /// The item of a hand fact: its quote spans the whole line, and it has the label and authority of that line.
    private func handItem(_ fact: HandFact, words: String, of spec: HelperSpec, quoting line: StoredLine) throws -> Item
    {
        let now = clock()
        var fields = [
            "kind": fact.kind, "person": fact.person, "project": fact.project, spec.title: words, "stance": "said",
        ]
        if let due = fact.due { fields[Item.dueField] = try Coding.json(Due.stated(on: due)) }
        let standing = Standing(citing: [line.evidence], facts: [], window: [line.evidence])
        return Item(
            task: spec.task, day: WorkDay(containing: now), scope: "", source: .typed, citeFirst: 0, citeLast: 0,
            start: now, end: now, fields: fields, quote: words, run: nil,
            quoteSpan: line.text.span(of: words).map {
                QuoteSpan(line: line.number, part: 0, start: $0.lowerBound, end: $0.upperBound)
            }, label: standing.label, authority: standing.authority)
    }
}

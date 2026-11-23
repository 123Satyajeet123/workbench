import Foundation
import GRDB

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
    /// Adds a fact the person typed: no model run, the person's own words, and the machine's lifecycle and timers as for
    /// any fact. It uses the one insert of items. Returns nil when the words or the kind do not fit the machine.
    @discardableResult
    public func addFact(_ fact: HandFact, to spec: HelperSpec = .team) throws -> Int64? {
        guard spec.takesHandFacts, spec.factKinds.contains(fact.kind), let words = fact.text.cleaned else { return nil }
        let now = clock()
        var fields = [
            "kind": fact.kind, "person": fact.person, "project": fact.project, spec.title: words, "stance": "said",
        ]
        if let due = fact.due { fields[Item.dueField] = try Coding.json(Due.stated(on: due)) }
        let item = Item(
            task: spec.task, day: WorkDay(containing: now), scope: "", source: .typed, citeFirst: 0, citeLast: 0,
            start: now, end: now, fields: fields, quote: words, run: nil, authority: .ownWords)
        return try writer.write { db in
            let id = try insert(item, day: item.day, scope: "", db)
            if spec.lifecycle != nil { try reconcileTimers(db, item: id) }
            return id
        }
    }
}

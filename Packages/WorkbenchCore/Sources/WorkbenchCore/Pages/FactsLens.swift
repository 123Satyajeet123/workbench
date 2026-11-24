import Foundation

/// Why a fact asks for the person. Worked out from the spec's own marks, the fact's due time and the clock; no words.
public enum FactNeed: Equatable, Sendable {
    /// The fact carries the spec's mark for "asks the person".
    case asks
    /// The fact is open and its due time has passed, by this many whole days (0 for less than a day).
    case late(days: Int)
    /// The fact is open and the spec gives one of its values a bad tone.
    case trouble(value: String)
}

/// What a machine's spec and the clock say about its facts: which are open, which need the person, and how a group of
/// them is counted. It is the one place that reads a spec for a facts view, for every layout.
public struct FactsLens: Sendable {
    public var spec: HelperSpec
    public var now: Date
    public var attention: HelperSpec.Attention

    public init(spec: HelperSpec, now: Date, attention: HelperSpec.Attention = .builtIn) {
        self.spec = spec
        self.now = now
        self.attention = attention
    }

    public func isOpen(_ item: Item) -> Bool { item.isOpen(in: spec.lifecycle, at: now) }

    /// What asks the person in a fact; empty for a fact that is not open.
    public func needs(of item: Item) -> [FactNeed] {
        guard isOpen(item) else { return [] }
        var needs: [FactNeed] = []
        if item.carries(attention.asksMe) { needs.append(.asks) }
        if item.isPastDue(at: now), let utc = item.due?.utc {
            needs.append(.late(days: Int(now.timeIntervalSince(utc) / 86_400)))
        }
        for field in spec.fields {
            let value = item[field.name]
            if spec.tones[value] == .bad { needs.append(.trouble(value: value)) }
        }
        return needs
    }

    public func tone(of value: String) -> HelperSpec.Tone { spec.tones[value] ?? .neutral }

    /// The values of `field` that facts have, with how many facts have each: the field's own order when it has a fixed
    /// set of values, else the most first. Facts with no value are not counted.
    public func tally(of facts: [Item], by field: String) -> [(value: String, count: Int)] {
        let counts = Dictionary(grouping: facts.map { $0[field] }.filter { !$0.isEmpty }, by: { $0 })
            .map { (value: $0.key, count: $0.value.count) }
        let declared = spec.fields.first { $0.name == field }?.kind.fixedValues ?? []
        return counts.sorted { first, second in
            switch (declared.firstIndex(of: first.value), declared.firstIndex(of: second.value)) {
            case (let a?, let b?): a < b
            case (_?, nil): true
            case (nil, _?): false
            default: (second.count, first.value) < (first.count, second.value)
            }
        }
    }

    /// The fact most recently read.
    public func newest(of facts: [Item]) -> Item? { facts.max { ($0.day, $0.start) < ($1.day, $1.start) } }

    /// Whether `first` comes before `second` when the person is to be served first: facts that need them, then open
    /// ones, soonest due first, then the newest.
    func isMoreUrgent(_ first: Item, than second: Item) -> Bool {
        func rank(_ item: Item) -> (Int, Int, Date, Date) {
            (
                needs(of: item).isEmpty ? 1 : 0, isOpen(item) ? 0 : 1, item.due?.utc ?? .distantFuture,
                Date(timeIntervalSinceReferenceDate: -item.start.timeIntervalSinceReferenceDate)
            )
        }
        return rank(first) < rank(second)
    }
}

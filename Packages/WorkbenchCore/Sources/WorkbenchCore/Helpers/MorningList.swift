import Foundation

/// One line of the morning list: an open fact or a finding, and why it is there.
public struct Need: Sendable, Equatable, Identifiable {
    public enum Reason: Sendable, Equatable {
        /// A finding of the derailment watch that asks the founder to act today.
        case act
        /// A finding worth a look soon.
        case watch
        /// An open fact that asks the founder.
        case asks
        /// An open fact the founder owns.
        case owned
        /// An open fact due on this day or before it.
        case due(WorkDay)
        /// An open fact whose timer fired: its time has come, or it waited longer than its policy allows.
        case timerFired
        /// A model read that a line closes it, with the outcome it read.
        case proposedClose(outcome: String)
        /// An open fact someone else owns, which the founder asked for.
        case owedToMe
        /// An open fact someone else owns.
        case waiting
        /// A passed deal whose revisit day has come.
        case revisit
        /// Bad news about a company the investor follows, from a trusted feed. Information, not a task.
        case news
    }

    public var item: Item
    public var reason: Reason

    public var id: Int64? { item.id }
}

/// The facts of one owner in the list "Waiting on". Groups are ordered by name and carry no count, so the list cannot
/// rank people.
public struct OwnerGroup: Sendable, Equatable, Identifiable {
    public var owner: String
    public var needs: [Need]

    public var id: String { owner }
}

/// One section of the morning list.
public struct MorningSection: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case toConfirm, slipped, owe, findings, revisits, owedToMe, waitingOn, news

        /// Whether the lines ask the person to do something. "Owed to me" and "Waiting on" only inform.
        public var needsPerson: Bool { self != .owedToMe && self != .waitingOn }
    }

    public var kind: Kind
    public var needs: [Need]
    /// The lines of `waitingOn` by owner; empty for every other kind, whose lines are in `needs`.
    public var owners: [OwnerGroup] = []

    public var id: Kind { kind }
    /// Every line of the section, by owner for `waitingOn`.
    public var lines: [Need] { kind == .waitingOn ? owners.flatMap(\.needs) : needs }
}

extension Item {
    /// Who owns the fact now: the person it was handed to, else the value of its owner field.
    func owner(in field: String) -> String { (handedTo ?? self[field]).trimmingCharacters(in: .whitespaces) }

    /// The instant its due time passed, when it has passed.
    func isPastDue(at now: Date) -> Bool { due?.utc.map { $0 < now } ?? false }
}

/// What the morning list reads: fields a model filled, the due time and lifecycle events code resolved, and the
/// founder's own marks. Code reads no words.
public struct MorningInput: Sendable {
    /// Open facts, whatever their owner.
    public var facts: [Item]
    public var findings: [Item] = []
    public var revisits: [Item] = []
    public var news: [Item] = []
    /// The facts that have a fired timer nobody cancelled.
    public var firedTimers: Set<Int64> = []
    /// The founder's name as the owner field of a fact writes it.
    public var me: String
    /// The field that names who owns a fact, from the lifecycle of the fact's own machine; nil when its facts name no
    /// owner, so none is the person's own and none waits on someone.
    public var ownerField: @Sendable (Item) -> String? = { _ in nil }
    /// The field that names who asked for a fact, from the lifecycle of the fact's own machine; nil when it has none.
    public var askerField: @Sendable (Item) -> String? = { _ in nil }
    public var attention: HelperSpec.Attention = .builtIn

    public init(facts: [Item], me: String) {
        self.facts = facts
        self.me = me
    }
}

public enum MorningList {
    /// The sections of the morning list at `now`, each fact in the first one it fits. A closed, hidden, snoozed or
    /// wrong item is left out; so is a revisit before its day and news that is not bad or not from a trusted feed.
    /// Sections with no lines are left out. Order: a close for the person to confirm; slipped; what the person owes;
    /// findings; revisits; owed to the person; waiting on others, grouped by owner; bad news.
    public static func pick(_ input: MorningInput, now: Date, zone: TimeZone = .current) -> [MorningSection] {
        let today = WorkDay(containing: now, calendar: .gregorian(in: zone))
        let open = input.facts.filter { $0.closed == nil && $0.isListed(at: now) }
        var sections: [MorningSection.Kind: [Need]] = [:]
        var waiting: [Need] = []
        for fact in open.sorted(by: soonestFirst) {
            let place = place(of: fact, input, now: now)
            if place.section == .waitingOn {
                waiting.append(place.need)
            } else {
                sections[place.section, default: []].append(place.need)
            }
        }
        sections[.findings] = findings(input, now: now)
        sections[.revisits] = revisits(input, today: today, now: now)
        sections[.news] = input.news.filter { $0.closed == nil && $0.isListed(at: now) && $0.isTrustedBadNews }
            .map { Need(item: $0, reason: .news) }
        return MorningSection.Kind.allCases.compactMap { kind in
            if kind == .waitingOn {
                let owners = owners(of: waiting, input)
                return owners.isEmpty ? nil : MorningSection(kind: kind, needs: [], owners: owners)
            }
            return sections[kind].flatMap { $0.isEmpty ? nil : MorningSection(kind: kind, needs: $0) }
        }
    }

    /// The facts the person has to do something about: the lines of every section that asks them.
    public static func needsCount(_ sections: [MorningSection]) -> Int {
        sections.filter(\.kind.needsPerson).reduce(0) { $0 + $1.lines.count }
    }

    private static func place(of fact: Item, _ input: MorningInput, now: Date) -> (
        section: MorningSection.Kind, need: Need
    ) {
        let isMine = !input.me.isEmpty && owner(of: fact, input)?.caseInsensitiveCompare(input.me) == .orderedSame
        let asksMe = fact.handedTo == nil && fact.carries(input.attention.asksMe)
        if let proposed = fact.proposedClose {
            return (.toConfirm, Need(item: fact, reason: .proposedClose(outcome: proposed.outcome)))
        }
        if fact.isPastDue(at: now), let day = fact.dueDay {
            return (.slipped, Need(item: fact, reason: .due(day)))
        }
        if fact.id.map(input.firedTimers.contains) == true { return (.slipped, Need(item: fact, reason: .timerFired)) }
        if asksMe { return (.owe, Need(item: fact, reason: .asks)) }
        if isMine { return (.owe, Need(item: fact, reason: .owned)) }
        if let asker = input.askerField(fact), !input.me.isEmpty,
            fact[asker].caseInsensitiveCompare(input.me) == .orderedSame
        {
            return (.owedToMe, Need(item: fact, reason: .owedToMe))
        }
        return (.waitingOn, Need(item: fact, reason: .waiting))
    }

    private static func findings(_ input: MorningInput, now: Date) -> [Need] {
        let listed = input.findings.filter { $0.closed == nil && $0.isListed(at: now) }
        return listed.filter { $0.carries(input.attention.act) }.map { Need(item: $0, reason: .act) }
            + listed.filter { $0.carries(input.attention.watch) }.map { Need(item: $0, reason: .watch) }
    }

    private static func revisits(_ input: MorningInput, today: WorkDay, now: Date) -> [Need] {
        input.revisits.filter {
            $0.closed == nil && $0.isListed(at: now) && ($0.dueDay.map { $0 <= today } ?? false)
        }
        .sorted { ($0.dueDay ?? today) < ($1.dueDay ?? today) }.map { Need(item: $0, reason: .revisit) }
    }

    /// The facts by owner, owners by name. A fact with no owner named is left out: nobody is waited on.
    private static func owners(of needs: [Need], _ input: MorningInput) -> [OwnerGroup] {
        let owned = needs.compactMap { need in owner(of: need.item, input).map { (owner: $0, need: need) } }
        return Dictionary(grouping: owned, by: \.owner).map { OwnerGroup(owner: $0.key, needs: $0.value.map(\.need)) }
            .sorted { $0.owner.localizedCaseInsensitiveCompare($1.owner) == .orderedAscending }
    }

    /// Who owns the fact by its own machine's owner field; nil when that machine names no owner or the fact names none.
    private static func owner(of fact: Item, _ input: MorningInput) -> String? {
        input.ownerField(fact).map(fact.owner(in:)).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Facts with a due time first, the soonest first, then by store id.
    private static func soonestFirst(_ a: Item, _ b: Item) -> Bool {
        switch (a.due?.utc, b.due?.utc) {
        case (let first?, let second?) where first != second: first < second
        case (_?, nil): true
        case (nil, _?): false
        default: (a.id ?? 0) < (b.id ?? 0)
        }
    }
}

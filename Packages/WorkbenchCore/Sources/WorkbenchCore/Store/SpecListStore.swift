import Foundation

extension Store {
    /// Saves the news feeds a machine fetches. Like a brief edit, it is a new version of the machine.
    public func setFeeds(_ machine: Machine, _ feeds: [NewsFeed]) throws {
        guard feeds.allSatisfy({ $0.name.cleaned != nil }) else { return }
        var spec = machine.spec
        spec.feeds = feeds
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }

    /// Saves the claim types a machine checks. A list with no type, a nameless type or a repeated id is refused.
    public func setClaimTypes(_ machine: Machine, _ types: [ClaimType]) throws {
        guard !types.isEmpty, Set(types.map(\.id)).count == types.count,
            types.allSatisfy({ $0.label.cleaned != nil && $0.proof.cleaned != nil })
        else { return }
        var spec = machine.spec
        spec.claimTypes = types
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }

    func apply(_ answer: SetupAnswer, to machine: Machine) throws {
        switch answer {
        case .criteria(let criteria): try setCriteria(machine, criteria)
        case .feeds(let feeds): try setFeeds(machine, feeds)
        case .claimTypes(let types): try setClaimTypes(machine, types)
        }
    }
}

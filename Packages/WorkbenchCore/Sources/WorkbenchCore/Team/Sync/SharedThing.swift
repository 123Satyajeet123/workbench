import Foundation

/// What an envelope holds once opened: each thing a person shares with the team.
public enum SharedThing: Codable, Sendable, Equatable {
    case event(WorkEvent)
    case day(SharedDay)
    case machine(SharedMachine)
    case review(MachineReview)
    /// The author withdraws what they shared under `key`. People who already read it still have it.
    case retraction(key: String, by: String)

    /// The person who signed it must be this person, or the envelope is refused: no one writes in another's name.
    public var author: String {
        switch self {
        case .event(let event): event.author
        case .day(let day): day.author
        case .machine(let machine): machine.author
        case .review(let review): review.reviewer
        case .retraction(_, let author): author
        }
    }

    /// What a later version or a retraction replaces. An event is never replaced: its key is its id.
    public var key: String {
        switch self {
        case .event(let event): event.id
        case .day(let day): SharedDay.key(author: day.author, task: day.task, day: day.day)
        case .machine(let machine): SharedMachine.key(author: machine.author, task: machine.spec.task)
        case .review(let review): "review/" + review.id
        case .retraction(let key, _): key
        }
    }

    /// The people named as readers, by name; nil means the whole team. A work event with a linked item goes only to
    /// the item's audience, a day only to the day's.
    public var audience: [String]? {
        switch self {
        case .event(let event): event.item?.audience
        case .day(let day): day.audience
        default: nil
        }
    }

    /// The clock the envelope takes, when the thing has one of its own.
    public var clock: Int? {
        if case .event(let event) = self { return event.clock }
        return nil
    }

    func encoded() throws -> Data { Data(try Coding.json(self).utf8) }

    init(decoding data: Data) throws { self = try Coding.value(Self.self, from: String(decoding: data, as: UTF8.self)) }
}

extension SharedDay {
    /// What a later share of the same day, or its withdrawal, replaces.
    public static func key(author: String, task: String, day: String) -> String { "day/\(author)/\(task)/\(day)" }
}

extension SharedMachine {
    public static func key(author: String, task: String) -> String { "machine/\(author)/\(task)" }
}

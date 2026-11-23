import Foundation

public enum Mover: Sendable, Equatable {
    case person, machine
}

public enum MoveRefusal: Error, Equatable {
    case unknownStage(StageID)
    case retiredStage(StageID)
    case missingFacts([FieldID])
}

/// A move that was allowed: the stage to write as the event text, the stage events it replaces, and the timer
/// rules of the stage it enters. The rules are data until timers exist.
public struct StageMove: Sendable, Equatable {
    public var stage: StageID
    public var replaces: [String]
    public var after: [TimerRule]

    public func event(object: String, author: String, clock: Int, at: Date) -> WorkEvent {
        WorkEvent(object: object, author: author, clock: clock, at: at, kind: .stage, text: stage, replaces: replaces)
    }
}

extension ObjectType {
    /// Moves `object` to `stage`. A person moves it freely. A machine must cite a fact for every field the stage
    /// requires. The move replaces every stage event that stands, so it also settles a conflict.
    public func move(
        _ object: WorkObject, to stage: StageID, by mover: Mover, facts: [FieldID: FactID] = [:]
    ) throws -> StageMove {
        guard let target = self.stage(stage) else { throw MoveRefusal.unknownStage(stage) }
        guard !target.retired else { throw MoveRefusal.retiredStage(stage) }
        if mover == .machine {
            let missing = target.requires.filter { facts[$0]?.isEmpty ?? true }
            guard missing.isEmpty else { throw MoveRefusal.missingFacts(missing) }
        }
        return StageMove(stage: target.id, replaces: object.stageHeads, after: target.after)
    }
}

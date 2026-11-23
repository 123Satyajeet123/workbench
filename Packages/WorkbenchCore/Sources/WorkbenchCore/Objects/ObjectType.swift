import Foundation

public typealias TypeID = String
public typealias StageID = String
public typealias FieldID = String
public typealias FactID = String

/// What code may know about a stage. Code reads the meaning, never the label. The meaning of one stage id never
/// changes; a new meaning is a new stage id.
public enum Meaning: String, Codable, Sendable, Equatable {
    case open, waiting, won, lost, watch
}

public enum FieldKind: Codable, Sendable, Equatable {
    case text, date, person, money
    case choice([OptionDef])
}

public struct OptionDef: Codable, Sendable, Equatable {
    public let id: String
    public var label: String
    public var retired = false

    public init(id: String, label: String, retired: Bool = false) {
        self.id = id
        self.label = label
        self.retired = retired
    }
}

public struct FieldDef: Codable, Sendable, Equatable {
    public let id: FieldID
    public var label: String
    public var kind: FieldKind
    public var retired = false

    public init(id: FieldID, label: String, kind: FieldKind, retired: Bool = false) {
        self.id = id
        self.label = label
        self.kind = kind
        self.retired = retired
    }
}

/// On entering a stage, a date field gets a timer row. Timer rows are made in a later step; here the rule is data.
public struct TimerRule: Codable, Sendable, Equatable {
    public let field: FieldID
    public var defaultAfterDays: Int?
    public var needsPerson = true

    public init(field: FieldID, defaultAfterDays: Int? = nil, needsPerson: Bool = true) {
        self.field = field
        self.defaultAfterDays = defaultAfterDays
        self.needsPerson = needsPerson
    }
}

public struct StageDef: Codable, Sendable, Equatable, Identifiable {
    public let id: StageID
    public var label: String
    public var order: Double
    public let meaning: Meaning
    /// Fields a machine move must cite a fact for. A person move is free.
    public var requires: [FieldID]
    public var after: [TimerRule]
    /// For a waiting stage: the stage the object goes to when its wait ends.
    public var resumes: StageID?
    /// A retired stage is still drawn for objects that stand in it, and no move may enter it.
    public var retired: Bool

    public init(
        id: StageID, label: String, order: Double, meaning: Meaning, requires: [FieldID] = [],
        after: [TimerRule] = [], resumes: StageID? = nil, retired: Bool = false
    ) {
        self.id = id
        self.label = label
        self.order = order
        self.meaning = meaning
        self.requires = requires
        self.after = after
        self.resumes = resumes
        self.retired = retired
    }
}

/// How one object kind is answered by many people. Designed here, built later.
public struct ResponseRule: Codable, Sendable, Equatable {
    public var kinds: [OptionDef]
    public var needs: Int

    public init(kinds: [OptionDef], needs: Int) {
        self.kinds = kinds
        self.needs = needs
    }
}

/// A kind of work object as data: its fields and stages. A change makes a new version, and old events still fold.
public struct ObjectType: Codable, Sendable, Equatable, Identifiable {
    public static let currentFormat = 1

    public let id: TypeID
    public var format = currentFormat
    public var version: Int
    public var noun: String
    public var fields: [FieldDef]
    public var stages: [StageDef]
    public var responses: ResponseRule?

    public init(
        id: TypeID, version: Int = 1, noun: String, fields: [FieldDef] = [], stages: [StageDef],
        responses: ResponseRule? = nil
    ) {
        self.id = id
        self.version = version
        self.noun = noun
        self.fields = fields
        self.stages = stages
        self.responses = responses
    }

    /// A kind no catalog lists. Every stage its objects stand in is read as a retired open stage.
    public static func unlisted(_ id: TypeID) -> ObjectType { ObjectType(id: id, noun: id, stages: []) }

    public var orderedStages: [StageDef] { stages.sorted { ($0.order, $0.id) < ($1.order, $1.id) } }

    /// Where a new object starts: the first stage that is not retired.
    public var entryStage: StageDef? { orderedStages.first { !$0.retired } }

    public func stage(_ id: StageID) -> StageDef? { stages.first { $0.id == id } }

    public func firstStage(meaning: Meaning) -> StageDef? {
        orderedStages.first { $0.meaning == meaning && !$0.retired }
    }

    /// The stage a stored stage text names. A new event holds the stage id. An event written before ids existed
    /// holds the label. Any other text is a retired open stage that keeps that text as its id and label.
    public func resolveStage(_ text: String) -> StageDef {
        stage(text) ?? stages.first { $0.label == text }
            ?? StageDef(id: text, label: text, order: .greatestFiniteMagnitude, meaning: .open, retired: true)
    }
}

public enum ObjectTypeError: Error, Equatable {
    case differentType
    case meaningChanged(StageID)
    case stageRemoved(StageID)
    case versionNotNext
}

extension ObjectType {
    /// The next version of this type. A label, an order, a rule or a new stage may change. The meaning of a stage
    /// may not, and a stage may not be removed: it is retired.
    public func revised(to next: ObjectType) throws -> ObjectType {
        guard next.id == id else { throw ObjectTypeError.differentType }
        guard next.version == version + 1 else { throw ObjectTypeError.versionNotNext }
        for stage in stages {
            guard let changed = next.stage(stage.id) else { throw ObjectTypeError.stageRemoved(stage.id) }
            guard changed.meaning == stage.meaning else { throw ObjectTypeError.meaningChanged(stage.id) }
        }
        return next
    }
}

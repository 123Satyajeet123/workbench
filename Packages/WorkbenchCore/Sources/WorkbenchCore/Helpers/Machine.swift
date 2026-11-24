import Foundation

/// A machine a person owns: a helper spec with a name, made from a template. The spec's task names its runs and items,
/// so a rename keeps them and their trust; a changed brief is a new prompt version that earns trust again.
public struct Machine: Sendable, Equatable, Identifiable {
    public enum State: String, Sendable, CaseIterable {
        case active, paused, deleted
    }

    public var id: Int64
    public var name: String
    public var template: String
    public var spec: HelperSpec
    public var state: State
    /// The machine's page in the tree. Its parent is the folder the machine lives in.
    public var page: WorkObjectID?
    /// The folder of the machine's page; nil when it has no page.
    public var folder: WorkObjectID?

    public var task: String { spec.task }

    public init(
        id: Int64, name: String, template: String, spec: HelperSpec, state: State, page: WorkObjectID? = nil,
        folder: WorkObjectID? = nil
    ) {
        self.id = id
        self.name = name
        self.template = template
        self.spec = spec
        self.state = state
        self.page = page
        self.folder = folder
    }
}

public struct Team: Sendable, Equatable {
    public struct Person: Sendable, Equatable, Identifiable {
        public var id: Int64?
        public var name: String
        public var role: String
        public var isMe: Bool

        public init(id: Int64? = nil, name: String, role: String, isMe: Bool = false) {
            self.id = id
            self.name = name
            self.role = role
            self.isMe = isMe
        }
    }

    public var name: String
    public var people: [Person]

    public init(name: String, people: [Person]) {
        self.name = name
        self.people = people
    }
}

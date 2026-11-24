import Foundation

/// What a delete of a source's kind removes outside the evidence store: rows of the capture log, and the rows of the
/// tables the source keeps. The delete reads this and names no source.
public struct Forgetting: Sendable, Equatable {
    /// A table the source keeps, and how a row of it ages.
    public struct Table: Sendable, Equatable {
        /// How the age column is written.
        public enum Age: Sendable, Equatable {
            /// A time, as the store writes one.
            case instant
            /// A work day, written yyyy-MM-dd.
            case day
        }

        public let name: String
        public let ageColumn: String
        public let age: Age
        /// A condition a row must meet to go, such as a call that is not still being recorded.
        public let condition: String?
        /// The column that holds the path of a folder to remove after the row goes.
        public let folderColumn: String?

        public init(
            name: String, ageColumn: String, age: Age = .instant, condition: String? = nil,
            folderColumn: String? = nil
        ) {
            self.name = name
            self.ageColumn = ageColumn
            self.age = age
            self.condition = condition
            self.folderColumn = folderColumn
        }
    }

    /// The kinds of row of the capture log that belong to the source.
    public let activity: [Activity.Kind]
    public let tables: [Table]

    public init(activity: [Activity.Kind] = [], tables: [Table] = []) {
        self.activity = activity
        self.tables = tables
    }
}

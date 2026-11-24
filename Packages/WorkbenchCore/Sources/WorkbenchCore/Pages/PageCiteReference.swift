import Foundation

extension PageCite {
    /// The cite as one word a view can hold and give back: `fact:12`, `note:<block>` or `request`.
    public var reference: String { stored }

    public init?(reference: String) { self.init(stored: reference) }
}

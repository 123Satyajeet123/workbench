import Foundation

/// The blocks of the document that no stored page holds: what stands above the page's own blocks, and what stands below
/// them. Each is worked out from the machine as it is now, so the page shows it again when the machine changes.
struct DocumentBlocks: Equatable {
    var head: [PageBlockData] = []
    var tail: [PageBlockData] = []

    static let none = DocumentBlocks()

    var all: [PageBlockData] { head + tail }
    var ids: Set<String> { Set(all.map(\.id)) }
}

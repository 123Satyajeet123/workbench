import Foundation
import WorkbenchCore

/// The stored lines of some chats, one day at a time, as the labelling tool shows them.
public struct StoreLines: LabelLineSource {
    public let store: Store
    public let chats: [String]

    public init(store: Store, chats: [String]) {
        self.store = store
        self.chats = chats
    }

    public func lines(on day: WorkDay) throws -> [LabelLine] {
        try store.queries.currentLines(in: chats, from: day.start, to: day.end).filter { !$0.isTombstone }.map {
            LabelLine(day: day, id: $0.lineID.map { String(format: "%02x", $0) }.joined(), text: $0.text)
        }
    }
}

extension KalLabelling {
    /// Labels a week of the chats of the store in `directory`, reading a copy of it: the original is never opened, so
    /// it is never migrated or changed, and the copy is deleted when the run ends.
    @discardableResult
    public static func run(
        onCopyOf directory: URL, chats: [String], terms: [String], weekStarting first: WorkDay,
        ask: (LabelLine, _ number: Int, _ of: Int) -> LabelAnswer, record: (LabelRecord) throws -> Void
    ) throws -> Int {
        try Store.withCopy(of: directory) { store in
            try KalLabelling(source: StoreLines(store: store, chats: chats), terms: terms)
                .run(weekStarting: first, ask: ask, record: record)
        }
    }
}

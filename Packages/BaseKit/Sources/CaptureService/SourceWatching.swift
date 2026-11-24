import Foundation
import Kernel
import LocalSources
import WorkbenchCore

/// A reader that keeps the copy of one source current while the app runs.
@MainActor
protocol SourceWatching {
    func stop()
}

extension WhatsAppIngestWatch: SourceWatching {}

/// How to start the watcher of one source. A source with no entry here has no watcher: it is read when asked.
struct SourceWatcher {
    let descriptor: SourceDescriptor
    /// `report` gets what each ingest reported: the failures in plain words, or nil when it read and wrote cleanly.
    let start: @MainActor (Store, PersonID, @escaping @MainActor @Sendable (String?) -> Void) -> any SourceWatching

    static let all = [
        SourceWatcher(descriptor: .whatsAppChat) { WhatsAppIngestWatch(store: $0, owner: $1, onIngest: $2) }
    ]
}

import Foundation
import Kernel
import WorkbenchCore

/// Keeps our copy of the allowed WhatsApp chats current while the app runs: one ingest now, and one after WhatsApp's
/// store or its write-ahead log changes. A message deleted for everyone is rewritten in that store, so an ingest after
/// the change erases our copy of its text within `period`. It listens to file events only: it reads nothing of the
/// store until an ingest runs, and an ingest reads only the chats the person allowed.
@MainActor
public final class WhatsAppIngestWatch {
    public static let period: Duration = .seconds(5)
    nonisolated static let storeFiles: Set<String> = ["ChatStorage.sqlite", "ChatStorage.sqlite-wal"]

    private let throttle: ChangeThrottle
    private var watcher: FileWatcher?

    /// `onIngest` gets what each ingest reported: the failures in plain words, or nil when it read and wrote cleanly.
    public init(
        store: Store, owner: PersonID, container: URL = WhatsAppChatReader.defaultContainer,
        period: Duration = period,
        latency: TimeInterval = 1.0, onIngest: @escaping @MainActor @Sendable (String?) -> Void = { _ in }
    ) {
        throttle = ChangeThrottle(period: period) {
            let failure = await Self.ingest(store: store, owner: owner, container: container)
            await onIngest(failure)
        }
        watcher = FileWatcher(folders: [container], latency: latency) { [throttle] _, path in
            guard Self.isStoreFile(path) else { return }
            Task { await throttle.changed() }
        }
        Task { await throttle.changed() }
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        Task { [throttle] in await throttle.stop() }
    }

    nonisolated static func isStoreFile(_ path: String) -> Bool {
        storeFiles.contains(URL(fileURLWithPath: path).lastPathComponent)
    }

    /// Reads every allowed chat and writes what is new. Returns why it failed, or nil.
    static func ingest(store: Store, owner: PersonID, container: URL) async -> String? {
        do {
            let chats = try store.currentPolicy().allowList[.whatsapp] ?? []
            guard !chats.isEmpty else { return nil }
            let reader = WhatsAppChatReader(container: container, chatJIDs: chats.sorted(), policy: store)
            let report = try await store.ingest(reader, owner: owner, now: store.clock())
            return report.failures.first.map { "Could not keep \($0.label): \($0.error.localizedDescription)" }
        } catch {
            return "Could not keep WhatsApp chats: \(error.localizedDescription)"
        }
    }
}

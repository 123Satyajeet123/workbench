import Foundation
import Kernel
import WorkbenchCore

/// Keeps our copy of the allowed WhatsApp chats current while the app runs: one ingest now, and one after WhatsApp's
/// store changes. It asks the store's one read-only connection for its change stamp every `pollInterval` (a cheap
/// `PRAGMA data_version`, no copy and no open transaction). A message deleted for everyone is rewritten in that store,
/// so an ingest after the change erases our copy of its text within `period` plus one poll. It reads nothing of the
/// store until an ingest runs, and an ingest reads only the chats the person allowed.
@MainActor
public final class WhatsAppIngestWatch {
    public static let period: Duration = .seconds(5)
    public static let pollInterval: Duration = .seconds(2)

    private let throttle: ChangeThrottle
    private var poller: Task<Void, Never>?

    /// `onIngest` gets what each ingest reported: the failures in plain words, or nil when it read and wrote cleanly.
    public init(
        store: Store, owner: PersonID, container: URL = WhatsAppChatReader.defaultContainer,
        period: Duration = period, pollInterval: Duration = pollInterval,
        onIngest: @escaping @MainActor @Sendable (String?) -> Void = { _ in }
    ) {
        let throttle = ChangeThrottle(period: period) {
            let failure = await Self.ingest(store: store, owner: owner, container: container)
            await onIngest(failure)
        }
        self.throttle = throttle
        let connection = WhatsAppStoreConnection.shared(for: container)
        poller = Task.detached {
            var last: StoreStamp?
            while !Task.isCancelled {
                let stamp = connection.stamp()
                if stamp != last {
                    last = stamp
                    await throttle.changed()
                }
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    public func stop() {
        poller?.cancel()
        poller = nil
        Task { [throttle] in await throttle.stop() }
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

import Foundation
import Kernel
import Lines
import LocalSources
import WorkbenchCore

/// Writes the deletions Telegram reported. A deletion is first noted in the store (`Store.noteRevokes`), so it is not
/// lost while the writer cannot run; `apply` then writes a tombstone for each noted message through `Store.ingest`, the
/// writer's one revoke path: the text lines of the message and every copy of their words are erased, as for a
/// WhatsApp message deleted for everyone. A note goes once its tombstone is written.
public enum TelegramRevoke {
    /// Returns why a deletion could not be written yet, or nil. The notes of a failed chat stay for the next try.
    public static func apply(in store: Store, owner: PersonID) async -> String? {
        do {
            let allowed = try store.currentPolicy().allowList[.telegram] ?? []
            var failure: String?
            for (label, refs) in try store.pendingRevokes(kind: .telegram) {
                guard allowed.contains(label), let chat = Int64(label),
                    let audience = try store.agreedAudience(kind: .telegram, label: label)
                else {
                    try store.clearRevokes(kind: .telegram, label: label, messageRefs: refs)
                    continue
                }
                let reader = Reader(
                    chat: chat, messages: refs.compactMap(Int64.init), audience: audience, policy: store)
                let report = try await store.ingest(reader, owner: owner, now: store.clock())
                if let first = report.failures.first {
                    failure = "Could not erase a deleted Telegram message: \(first.error.localizedDescription)"
                } else {
                    try store.clearRevokes(kind: .telegram, label: label, messageRefs: refs)
                }
            }
            return failure
        } catch {
            return "Could not erase a deleted Telegram message: \(error.localizedDescription)"
        }
    }

    /// The tombstone of one message: no words, and the message's own ref, so the writer erases its text lines.
    static func tombstone(chat: Int64, message: Int64, readerVersion: String) -> ObservedLine? {
        guard let key = try? EntityKey.telegram(chatID: chat, messageID: message) else { return nil }
        return ObservedLine(
            line: .tombstone(entity: key, readerVersion: readerVersion), quality: .stable, messageRef: String(message))
    }

    /// A reading of tombstones only, under the audience the person confirmed.
    private struct Reader: EvidenceSource {
        let chat: Int64
        let messages: [Int64]
        let audience: AudienceDigest
        let policy: any CapturePolicyProvider

        var descriptor: SourceDescriptor { .telegramChat }

        func sightings(policy: CapturePolicy, now: Date) throws -> [ContainerSighting] { [] }

        func observe(state: @Sendable (String) throws -> ScanState, now: Date) async throws -> SourceRead {
            let label = String(chat)
            do {
                let grant = try await policy.grant(for: .telegram, label: label, at: now)
                let lines = messages.compactMap {
                    tombstone(chat: chat, message: $0, readerVersion: TelegramChatReader.readerVersion)
                }
                return SourceRead(
                    readings: [
                        SourceReading(
                            grant: grant, label: label, container: label, audience: audience, lines: lines,
                            cursorAfter: nil, readerVersion: TelegramChatReader.readerVersion)
                    ])
            } catch {
                return SourceRead(failures: [LabelFailure(label: label, error: error)])
            }
        }
    }
}

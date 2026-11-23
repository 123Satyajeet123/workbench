import Foundation
import Synchronization
import WorkbenchCore

/// The messages Telegram said were deleted for good, kept in a file beside the account so a deletion that arrives
/// between two reads is not lost. It holds ids and times, never words. An id is forgotten when it is older than the
/// retention, since no line that old is kept.
final class TelegramDeletions: Sendable {
    private let file: URL
    private let deleted: Mutex<[String: [String: Double]]>

    init(folder: URL) {
        file = folder.appending(path: "deleted-messages.json")
        let saved = (try? Data(contentsOf: file)).flatMap {
            try? JSONDecoder().decode([String: [String: Double]].self, from: $0)
        }
        deleted = Mutex(saved ?? [:])
    }

    func record(chat: Int64, messages: [Int64], at now: Date) {
        deleted.withLock { state in
            for message in messages { state[String(chat), default: [:]][String(message)] = now.timeIntervalSince1970 }
            Self.forget(before: now, in: &state)
            try? FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(state).write(to: file, options: .atomic)
        }
    }

    func messages(in chat: Int64, at now: Date) -> [Int64] {
        let cutoff = now.timeIntervalSince1970 - CapturePolicy.retention
        return deleted.withLock { state in
            (state[String(chat)] ?? [:]).filter { $0.value >= cutoff }.keys.compactMap(Int64.init).sorted()
        }
    }

    private static func forget(before now: Date, in state: inout [String: [String: Double]]) {
        let cutoff = now.timeIntervalSince1970 - CapturePolicy.retention
        for chat in state.keys { state[chat] = state[chat]?.filter { $0.value >= cutoff } }
    }
}

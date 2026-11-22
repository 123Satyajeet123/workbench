import CoreServices
import Foundation
import WorkbenchCore

/// File creations, changes and renames under the given folders, from FSEvents. Delivered on the main queue.
@MainActor
public final class FileWatcher {
    public enum Change: String, Sendable { case create, modify, rename }
    public typealias Handler = @MainActor (Change, String) -> Void

    public static var defaultFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appending(path: "Projects"), home.appending(path: "Documents")]
    }

    private var stream: FSEventStreamRef?
    private let handler: Handler

    /// `latency` is how long FSEvents gathers changes before it delivers them.
    public init(folders: [URL] = defaultFolders, latency: TimeInterval = 1.0, handler: @escaping Handler) {
        self.handler = handler
        start(
            paths: folders.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }, latency: latency)
    }

    isolated deinit { stop() }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    nonisolated static func change(forFlags flags: UInt32) -> Change? {
        guard flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 else { return nil }
        if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0 { return .rename }
        if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { return .create }
        if flags & UInt32(kFSEventStreamEventFlagItemModified) != 0 { return .modify }
        return nil
    }

    private func start(paths: [String], latency: TimeInterval) {
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, rawPaths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as? [String] ?? []
            let values = Array(UnsafeBufferPointer(start: flags, count: count))
            MainActor.assumeIsolated { watcher.deliver(paths: paths, flags: values) }
        }
        let options = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, paths as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                options)
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func deliver(paths: [String], flags: [UInt32]) {
        for (path, flag) in zip(paths, flags) {
            if let change = Self.change(forFlags: flag) { handler(change, path) }
        }
    }
}

import Foundation

@testable import WorkbenchUI

/// A private copy of the synthetic demo folder. The person's own folder is never named here.
struct DemoCopy {
    /// Files of a running app that a copy must not carry: its socket and its write lock.
    private static let skipped: Set<String> = ["pages.sock", "writer.lock"]

    let folder: URL

    /// Copies the demo folder, or says why it cannot: a folder with no builder marker is missing or half built.
    init(from source: URL, to folder: URL) throws {
        let marker = source.appending(path: Profile.builtMarker)
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw LiveFailure("the demo folder or its marker \(Profile.builtMarker) is missing")
        }
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: source.path) where !Self.skipped.contains(name)
        {
            try FileManager.default.copyItem(at: source.appending(path: name), to: folder.appending(path: name))
        }
        self.folder = folder
    }

    func delete() { try? FileManager.default.removeItem(at: folder) }
}

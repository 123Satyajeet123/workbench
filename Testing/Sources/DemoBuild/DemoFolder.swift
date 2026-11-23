import Foundation

enum DemoFolderError: Error, Equatable, LocalizedError {
    case isYourData(String)
    case notADemoFolder(String)

    var errorDescription: String? {
        switch self {
        case .isYourData(let path): "\(path) is, or holds, your own Workbench data. The builder never opens it."
        case .notADemoFolder(let path):
            "\(path) holds files that are not a demo. The builder only rebuilds a demo folder."
        }
    }
}

/// The folder the builder may make a demo in. It never is your data folder, never holds it, and never lies inside it.
enum DemoFolder {
    /// Makes `folder` empty and ready, or says why it must not. A folder with a demo's marker is rebuilt from nothing; an
    /// empty or missing one is made; any other folder is left as it is.
    static func prepare(_ folder: URL, yours: URL, marker: String) throws {
        let chosen = folder.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let real = yours.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard !chosen.starts(with: real), !real.starts(with: chosen) else {
            throw DemoFolderError.isYourData(folder.path)
        }
        let files = FileManager.default
        if files.fileExists(atPath: folder.path) {
            let holdsMarker = files.fileExists(atPath: folder.appending(path: marker).path)
            let isEmpty = (try? files.contentsOfDirectory(atPath: folder.path))?.isEmpty ?? false
            guard holdsMarker || isEmpty else { throw DemoFolderError.notADemoFolder(folder.path) }
            try files.removeItem(at: folder)
        }
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}

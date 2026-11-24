import Foundation

/// The connections file inside what the person picked: the Connections CSV itself, or the ZIP of their whole LinkedIn
/// data export. From a ZIP only that one entry is read (`unzip -p`), so the rest of the export never leaves the archive.
public enum LinkedInExportFile {
    public enum Failure: LocalizedError, Equatable {
        case noConnectionsFile
        case unreadableArchive(String)

        public var errorDescription: String? {
            switch self {
            case .noConnectionsFile:
                "This export has no Connections file. Pick the ZIP LinkedIn sent, or its Connections.csv."
            case .unreadableArchive(let reason): "The ZIP could not be read: \(reason)"
            }
        }
    }

    public static func connections(in file: URL) throws -> Data {
        guard file.pathExtension.lowercased() == "zip" else { return try Data(contentsOf: file) }
        return try entry(matching: "*Connections.csv", in: file)
    }

    private static func entry(matching pattern: String, in archive: URL) throws -> Data {
        let unzip = Process()
        unzip.executableURL = URL(filePath: "/usr/bin/unzip")
        unzip.arguments = ["-p", "-C", archive.path(percentEncoded: false), pattern]
        let output = Pipe()
        let errors = Pipe()
        unzip.standardOutput = output
        unzip.standardError = errors
        try unzip.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        unzip.waitUntilExit()
        switch unzip.terminationStatus {
        case 0 where !data.isEmpty: return data
        case 0, 11: throw Failure.noConnectionsFile
        default:
            throw Failure.unreadableArchive(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

import Foundation

extension Store {
    static let agentWorkFolder = "agent-work"

    /// The folder where a call to a model program spools its input and its reply. A call removes its files when it ends.
    public var agentWork: URL { directory.appending(path: Self.agentWorkFolder) }

    /// Removes the files of calls that did not end: a crash or a kill leaves them, with the words of the call in them.
    /// Only the app process opens the store, and it makes no call before the open ends, so no file here is in use.
    func clearCallFiles() throws {
        guard FileManager.default.fileExists(atPath: agentWork.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: agentWork, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

import Foundation

public enum FullDiskAccess {
    public static let defaultProbe = "/Library/Application Support/com.apple.TCC/TCC.db"

    public static func isGranted(probe: String = defaultProbe) -> Bool { openError(probe) == nil }

    static func openError(_ path: String) -> Int32? {
        let file = open(path, O_RDONLY)
        guard file < 0 else {
            close(file)
            return nil
        }
        return errno
    }
}

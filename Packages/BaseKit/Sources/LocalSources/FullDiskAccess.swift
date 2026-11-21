import Foundation

public enum FullDiskAccess {
    public static let defaultProbe = "/Library/Application Support/com.apple.TCC/TCC.db"

    public static func isGranted(probe: String = defaultProbe) -> Bool {
        let file = open(probe, O_RDONLY)
        guard file >= 0 else { return false }
        close(file)
        return true
    }
}

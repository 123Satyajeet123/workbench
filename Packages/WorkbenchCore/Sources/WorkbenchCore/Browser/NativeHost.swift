import CryptoKit
import Foundation

/// The registration of the native host `workbench-pages` with each browser the person enabled.
public enum NativeHost {
    public static let name = "com.hizen.workbench.pages"
    public static let fileName = name + ".json"

    public struct Failure: Sendable, Equatable {
        public let bundleID: String
        public let reason: String
    }

    /// The id Chromium gives an unpacked extension that has this public key in its manifest: the first 16 bytes of the
    /// key's SHA-256, each hex digit written as a letter from a to p.
    public static func extensionID(publicKey: String) -> String? {
        guard let key = Data(base64Encoded: publicKey) else { return nil }
        return SHA256.hash(data: key).prefix(16).flatMap { [$0 >> 4, $0 & 15] }
            .map { String(UnicodeScalar(97 + $0)) }.joined()
    }

    /// The id of the extension in `folder`, read from the public key in its manifest.
    public static func extensionID(inExtensionFolder folder: URL) -> String? {
        let manifest = try? JSONSerialization.jsonObject(
            with: Data(contentsOf: folder.appending(path: "manifest.json")))
        return ((manifest as? [String: Any])?["key"] as? String).flatMap(extensionID(publicKey:))
    }

    static func manifest(executable: URL, extensionID: String) -> Data {
        let manifest: [String: Any] = [
            "name": name,
            "description":
                "Workbench: keeps the text you see on a page, and Gmail threads in your named label, when your capture policy allows",
            "path": executable.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        return
            (try? JSONSerialization.data(
                withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    private struct ExtensionMissing: LocalizedError {
        var errorDescription: String? { "The browser extension is missing from the app, so the host cannot name it." }
    }

    /// Makes each browser's folder match the person's yes: an enabled browser gets the manifest that points at
    /// `executable` and names `extensionID`; any other browser has none. Returns the browsers that could not be set.
    public static func sync(
        _ installed: [InstalledBrowser], enabled: Set<String>, executable: URL, extensionID: String?
    ) -> [Failure] {
        installed.compactMap { browser in
            do {
                let file = browser.hostsFolder.appending(path: fileName)
                if enabled.contains(browser.id) {
                    guard let extensionID else { throw ExtensionMissing() }
                    try write(manifest(executable: executable, extensionID: extensionID), to: file)
                } else if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
                return nil
            } catch {
                return Failure(bundleID: browser.id, reason: error.localizedDescription)
            }
        }
    }

    private static func write(_ data: Data, to file: URL) throws {
        guard (try? Data(contentsOf: file)) != data else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

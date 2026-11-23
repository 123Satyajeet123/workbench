import Foundation

/// What an app bundle is, read from its structure and never from its name.
public enum WebBrowserApp {
    /// A web browser is the app that opens web addresses: its Info.plist claims the https scheme.
    public static func isBrowser(_ app: URL) -> Bool {
        schemes(of: app).contains("https")
    }

    /// A Chromium browser is a web browser that carries its own Chromium framework (`<Product> Framework.framework`).
    /// The framework is what runs the extension and starts the native host.
    public static func isChromium(_ app: URL) -> Bool {
        isBrowser(app) && holdsChromiumFramework(app)
    }

    static func info(of app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any]
    }

    private static func schemes(of app: URL) -> Set<String> {
        let types = info(of: app)?["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return Set(types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
    }

    private static func holdsChromiumFramework(_ app: URL) -> Bool {
        let frameworks = app.appending(path: "Contents/Frameworks")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: frameworks.path)) ?? []
        return names.contains { $0.hasSuffix(" Framework.framework") }
    }
}

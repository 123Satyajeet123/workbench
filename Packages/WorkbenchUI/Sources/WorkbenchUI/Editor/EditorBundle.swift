import Foundation
import WebKit

/// The files of the editor that ship in the app, and the only things the web view may load. It gets them through a
/// custom URL scheme: no file path and no network address ever reaches the web view.
final class EditorBundle: NSObject, WKURLSchemeHandler {
    static let scheme = "workbench-editor"
    static let home = URL(string: "\(scheme)://app/index.html")!

    /// Scripts and styles from this scheme only. Nothing else may load: no images, fonts, frames, connections or
    /// forms, and no inline script, no inline style and no `eval`.
    static let policy = [
        "default-src 'none'", "script-src \(scheme)://app", "style-src \(scheme)://app", "img-src 'none'",
        "font-src 'none'", "connect-src 'none'", "media-src 'none'", "object-src 'none'", "frame-src 'none'",
        "base-uri 'none'", "form-action 'none'",
    ].joined(separator: "; ")

    private static let types = ["html": "text/html", "js": "text/javascript", "css": "text/css"]
    private let folder: URL

    init(folder: URL = Bundle.module.url(forResource: "Editor", withExtension: nil)!) { self.folder = folder }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let file = file(for: url), let data = try? Data(contentsOf: file),
            let type = Self.types[file.pathExtension]
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let headers = [
            "Content-Type": "\(type); charset=utf-8", "Content-Length": String(data.count),
            "Content-Security-Policy": Self.policy, "Cache-Control": "no-store",
        ]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    /// The file a URL names: one of the files in the editor's folder, by name. A path with a folder in it names none.
    private func file(for url: URL) -> URL? {
        let name = url.path == "/" ? "index.html" : String(url.path.dropFirst())
        guard !name.contains("/"), !name.hasPrefix("."), Self.types[(name as NSString).pathExtension] != nil else {
            return nil
        }
        return folder.appending(path: name)
    }
}

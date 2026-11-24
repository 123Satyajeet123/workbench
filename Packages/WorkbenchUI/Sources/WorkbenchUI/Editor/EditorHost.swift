import AppKit
import SwiftUI
import WebKit

/// The web view of the editor and the typed bridge to it. It loads only the bundled files, has no network and opens no
/// window. Messages go out as typed values and come in as typed values; nothing else crosses.
final class EditorHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    var onMessage: ((EditorMessage) -> Void)?
    private(set) var problems: [String] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.setURLSchemeHandler(EditorBundle(), forURLScheme: EditorBundle.scheme)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configuration.userContentController.add(WeakHandler(self), name: "bridge")
    }

    func load() { webView.load(URLRequest(url: EditorBundle.home)) }

    func send(_ message: HostMessage) {
        guard let json = try? Self.encoder.encode(message), let text = String(data: json, encoding: .utf8) else {
            return
        }
        webView.callAsyncJavaScript(
            "window.bridge.receive(message)", arguments: ["message": text], in: nil, in: .page
        ) { [weak self] result in
            if case .failure(let error) = result { self?.problems.append(String(describing: error)) }
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String, let data = text.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(EditorMessage.self, from: data)
        else {
            problems.append("A message did not match the contract.")
            return
        }
        onMessage?(decoded)
    }

    /// Only the editor's own page may load. A link or a script that asks for anything else gets nothing.
    func webView(
        _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(action.request.url?.scheme == EditorBundle.scheme ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? { nil }
}

private final class WeakHandler: NSObject, WKScriptMessageHandler {
    private weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// The editor in a SwiftUI view.
struct EditorView: NSViewRepresentable {
    let host: EditorHost

    func makeNSView(context: Context) -> WKWebView { host.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

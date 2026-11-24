import AppKit
import WebKit

/// Types into a web view the way the keyboard and an input method do, with no window on screen: through the text input
/// client that the web view offers, and through its key handling.
@MainActor
public struct WebInput {
    public let webView: WKWebView

    public init(webView: WKWebView) { self.webView = webView }

    public func insertText(_ text: String) { send("insertText:replacementRange:", text) }
    public func markText(_ text: String) { send("setMarkedText:selectedRange:replacementRange:", text, marked: true) }

    private func send(_ name: String, _ text: String, marked: Bool = false) {
        let selector = NSSelectorFromString(name)
        let range = NSRange(location: NSNotFound, length: 0)
        if marked {
            typealias Function = @convention(c) (AnyObject, Selector, AnyObject, NSRange, NSRange) -> Void
            unsafeBitCast(webView.method(for: selector), to: Function.self)(
                webView, selector, text as NSString, NSRange(location: text.utf16.count, length: 0), range)
        } else {
            typealias Function = @convention(c) (AnyObject, Selector, AnyObject, NSRange) -> Void
            unsafeBitCast(webView.method(for: selector), to: Function.self)(
                webView, selector, text as NSString, range)
        }
    }

    /// A key's command, as the text input client takes it: `insertNewline:`, `deleteBackward:`.
    public func command(_ name: String) {
        let selector = NSSelectorFromString("doCommandBySelector:")
        typealias Function = @convention(c) (AnyObject, Selector, Selector) -> Void
        unsafeBitCast(webView.method(for: selector), to: Function.self)(
            webView, selector, NSSelectorFromString(name))
    }

    /// A key press through the web view's key handling.
    public func key(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: modifiers,
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: webView.window?.windowNumber ?? 0,
                    context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                    keyCode: code)
            else { return }
            if type == .keyDown { webView.keyDown(with: event) } else { webView.keyUp(with: event) }
        }
    }
}

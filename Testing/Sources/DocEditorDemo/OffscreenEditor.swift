import AppKit
import Foundation
import WebKit

@testable import WorkbenchUI

/// The editor in a web view inside a window that is never shown: no title bar, no style, never ordered front. The
/// checks drive it through its page and through the text input calls an input method makes.
@MainActor
final class OffscreenEditor {
    let host = EditorHost()
    let window: NSWindow

    init(size: CGSize = CGSize(width: 900, height: 1300), dark: Bool) {
        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.webView.frame = CGRect(origin: .zero, size: size)
        window.contentView = host.webView
    }

    /// The result of a script run in the editor's page. The script is a function body.
    @discardableResult
    func run(_ script: String) async throws -> Any? {
        try await host.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
    }

    func json(_ script: String) async throws -> String {
        let value = try await run("return JSON.stringify(await (async () => { \(script) })())")
        return value as? String ?? "null"
    }

    func waitUntil(_ script: String, seconds: Double = 5) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(seconds)
        while ContinuousClock.now < deadline {
            if (try await run("return Boolean(await (async () => { \(script) })())")) as? Bool == true { return true }
            try await Task.sleep(for: .milliseconds(25))
        }
        return false
    }

    // The web view takes text the way an input method gives it: through the text input client.
    func insertText(_ text: String) { send("insertText:replacementRange:", text) }
    func markText(_ text: String) { send("setMarkedText:selectedRange:replacementRange:", text, marked: true) }

    private func send(_ name: String, _ text: String, marked: Bool = false) {
        let selector = NSSelectorFromString(name)
        let range = NSRange(location: NSNotFound, length: 0)
        if marked {
            typealias Function = @convention(c) (AnyObject, Selector, AnyObject, NSRange, NSRange) -> Void
            unsafeBitCast(host.webView.method(for: selector), to: Function.self)(
                host.webView, selector, text as NSString, NSRange(location: text.utf16.count, length: 0), range)
        } else {
            typealias Function = @convention(c) (AnyObject, Selector, AnyObject, NSRange) -> Void
            unsafeBitCast(host.webView.method(for: selector), to: Function.self)(
                host.webView, selector, text as NSString, range)
        }
    }

    /// A key's command, as the text input client takes it: `insertNewline:`, `deleteBackward:`.
    func command(_ name: String) {
        let selector = NSSelectorFromString("doCommandBySelector:")
        typealias Function = @convention(c) (AnyObject, Selector, Selector) -> Void
        unsafeBitCast(host.webView.method(for: selector), to: Function.self)(
            host.webView, selector, NSSelectorFromString(name))
    }

    /// A key press through the web view's key handling, the way the keyboard gives it.
    func key(_ characters: String, code: UInt16) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)
            else { return }
            if type == .keyDown { host.webView.keyDown(with: event) } else { host.webView.keyUp(with: event) }
        }
    }

    func png(to file: URL) async throws {
        let image = try await host.webView.takeSnapshot(configuration: WKSnapshotConfiguration())
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { throw DemoFailure("no picture") }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: file)
    }
}

struct DemoFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The windows of this process that are on screen. A check that shows any has failed.
func windowsOnScreen() -> [String] {
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    return list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == getpid() }.map {
        "window \($0[kCGWindowNumber as String] ?? "?") at \($0[kCGWindowBounds as String] ?? "?")"
    }
}

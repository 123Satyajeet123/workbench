import AppKit
import ApplicationServices
import WorkbenchCore

/// The frontmost app, as NSWorkspace reports it. Read on the main thread; cheap.
public struct FrontApp: Sendable, Equatable {
    public var pid: pid_t
    public var name: String
    public var bundleID: String

    @MainActor
    public static func current(ownProcess: pid_t = getpid()) -> FrontApp? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ownProcess else { return nil }
        return FrontApp(pid: app.processIdentifier, name: app.localizedName ?? "", bundleID: app.bundleIdentifier ?? "")
    }
}

/// Reads the front window through the accessibility tree. Read only, with a short timeout on every call. Not thread
/// safe: one owner calls it.
public final class ScreenReader {
    public struct Limits: Sendable {
        public var nodes = 3000
        public var characters = 6000
        public var seconds: TimeInterval = 0.15
        public var addressBarNodes = 400
        public var callTimeout: Float = 0.1

        public init() {}
    }

    private static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField", "AXHeading", "AXLink"]

    private let limits: Limits
    private var addressBars: [Int: AXUIElement] = [:]
    private var knownDocuments: [Int: String] = [:]

    public init(limits: Limits = Limits()) { self.limits = limits }

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that opens Privacy & Security › Accessibility.
    public static func requestTrust() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// A few calls for title, document and focus; the text walk only when `withText` is true.
    public func read(_ app: FrontApp, withText: Bool) -> ScreenSnapshot {
        let element = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(element, limits.callTimeout)
        let window: AXUIElement? = attribute(element, kAXFocusedWindowAttribute)
        let windowID = window.map { Int(bitPattern: CFHash($0)) } ?? 0
        let focused: AXUIElement? = attribute(element, kAXFocusedUIElementAttribute)
        let secure = focused.flatMap { attribute($0, kAXSubroleAttribute) as String? } == "AXSecureTextField"
        let browser = CapturePolicy.browserBundleIDs.contains(app.bundleID)
        return ScreenSnapshot(
            app: app.name, bundleID: app.bundleID, windowID: windowID,
            document: window.map { document(of: $0, id: windowID, browser: browser, focused: focused) } ?? "",
            title: window.flatMap { attribute($0, kAXTitleAttribute) } ?? "",
            text: withText && !secure ? window.map(text(of:)) ?? "" : "", secureFocus: secure)
    }

    /// A read that fails, or an address bar the user is editing, says nothing new: the last known document stays.
    private func document(of window: AXUIElement, id: Int, browser: Bool, focused: AXUIElement?) -> String {
        if knownDocuments.count > 256 { knownDocuments.removeAll() }
        switch read(window, kAXDocumentAttribute) as Read<String> {
        case .value(let document) where !document.isEmpty: return remember(document, for: id)
        case .unknown: return knownDocuments[id] ?? ""
        case .value, .absent: break
        }
        guard browser else { return remember("", for: id) }
        if addressBars.count > 64 { addressBars.removeAll() }
        if addressBars[id] == nil { addressBars[id] = findAddressBar(in: window) }
        guard let bar = addressBars[id] else { return remember("", for: id) }
        if let focused, CFEqual(focused, bar) { return knownDocuments[id] ?? "" }
        switch read(bar, kAXValueAttribute) as Read<String> {
        case .value(let address): return remember(address, for: id)
        case .unknown: return knownDocuments[id] ?? ""
        case .absent:
            addressBars[id] = nil
            return remember("", for: id)
        }
    }

    private func remember(_ document: String, for id: Int) -> String {
        knownDocuments[id] = document
        return document
    }

    /// The first text field whose value reads as a web address.
    private func findAddressBar(in window: AXUIElement) -> AXUIElement? {
        var queue = [window]
        var next = 0
        while next < queue.count, next < limits.addressBarNodes {
            let element = queue[next]
            next += 1
            if attribute(element, kAXRoleAttribute) as String? == "AXTextField",
                let value: String = attribute(element, kAXValueAttribute), Self.looksLikeAddress(value)
            {
                return element
            }
            queue += attribute(element, kAXChildrenAttribute) ?? [AXUIElement]()
        }
        return nil
    }

    static func looksLikeAddress(_ value: String) -> Bool {
        !value.isEmpty && !value.contains(" ") && (value.contains("://") || value.contains("."))
    }

    private func text(of root: AXUIElement) -> String {
        let deadline = Date().addingTimeInterval(limits.seconds)
        var queue = [root]
        var next = 0
        var parts: [String] = []
        var characters = 0
        while next < queue.count, next < limits.nodes, characters < limits.characters, Date() < deadline {
            let element = queue[next]
            next += 1
            if let value = visibleText(of: element) {
                parts.append(value)
                characters += value.count
            }
            queue += attribute(element, kAXChildrenAttribute) ?? [AXUIElement]()
        }
        return String(parts.joined(separator: "\n").prefix(limits.characters))
    }

    /// For a text area, only the characters on screen (a terminal's scrollback stays out).
    private func visibleText(of element: AXUIElement) -> String? {
        guard let role: String = attribute(element, kAXRoleAttribute), Self.textRoles.contains(role),
            attribute(element, kAXSubroleAttribute) as String? != "AXSecureTextField"
        else { return nil }
        let raw: String? =
            visibleRange(of: element) ?? attribute(element, kAXValueAttribute) ?? attribute(element, kAXTitleAttribute)
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    private func visibleRange(of element: AXUIElement) -> String? {
        guard let range: AXValue = attribute(element, kAXVisibleCharacterRangeAttribute) else { return nil }
        var value: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, range, &value)
        return status == .success ? value as? String : nil
    }

    private enum Read<T> {
        case value(T)
        case absent, unknown
    }

    /// No value and an unsupported attribute mean absent; a timeout or any other error means unknown.
    private func read<T>(_ element: AXUIElement, _ name: String) -> Read<T> {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(element, name as CFString, &value) {
        case .success: return (value as? T).map(Read.value) ?? .absent
        case .noValue, .attributeUnsupported: return .absent
        default: return .unknown
        }
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        if case .value(let value) = read(element, name) as Read<T> { return value }
        return nil
    }
}

public enum Presence {
    /// Seconds since the last key, click or mouse move; infinite while the screen is locked.
    public static func idleSeconds() -> TimeInterval {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        if session?["CGSSessionScreenIsLocked"] as? Bool == true { return .infinity }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

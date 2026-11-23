import Foundation
import Testing

/// The shipped extension's scripts, by path inside the Extension folder.
enum ExtensionFiles {
    static let folder = NoEgressTests.repo.appending(path: "Extension")

    static func scripts() throws -> [String: String] {
        let walker = try #require(FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil))
        var scripts: [String: String] = [:]
        for case let file as URL in walker where file.pathExtension == "js" {
            scripts[String(file.path.dropFirst(folder.path.count + 1))] = try String(contentsOf: file, encoding: .utf8)
        }
        return scripts
    }

    /// The scripts that may open, read and close tabs: the page driver and the file that wires it.
    static let tabScripts: Set = ["background.js", "background/driver.js"]
    private static let tabCalls = [#"\bchrome\.tabs\b"#, #"\btabs\.(create|remove|group|sendMessage)\("#]

    /// Calls and assignments that click, type, focus, scroll, dispatch an event or change the page, inject a script,
    /// attach a debugger, or reach another tab or the page's own scripts. Comment lines are skipped. Only the service
    /// worker's scripts may post to their host, and only the page driver's scripts may use tabs, and then not to
    /// navigate, reload or script them.
    static func drivingCalls(in code: String, file: String) -> [String] {
        let banned =
            [
                #"dispatchEvent"#, #"\.click\("#, #"\.focus\("#, #"\.blur\("#, #"\.submit\("#, #"requestSubmit"#,
                #"KeyboardEvent"#, #"MouseEvent"#, #"PointerEvent"#, #"InputEvent"#, #"TouchEvent"#, #"WheelEvent"#,
                #"new\s+(Custom)?Event\b"#, #"execCommand"#, #"\.scrollIntoView"#, #"\.scrollTo\("#, #"\.select\("#,
                #"\.(innerHTML|outerHTML|innerText|textContent|value|checked|href|src)\s*=[^=]"#,
                #"(?<!tabs)\.(setAttribute|removeAttribute|appendChild|removeChild|append|prepend|remove|replaceWith)\("#,
                #"\.insertAdjacent\w*\("#, #"classList\.(add|remove|toggle)"#, #"\.style\.\w+\s*="#,
                #"document\.write"#, #"\bchrome\.(scripting|debugger|webRequest|userScripts)\b"#,
                #"\.(executeScript|insertCSS|removeCSS|registerContentScripts)\("#,
                #"\btabs\.(update|duplicate|reload|move|goBack|goForward|captureVisibleTab|discard|highlight)\("#,
            ] + (file.hasPrefix("background") ? [] : [#"\.postMessage\("#])
            + (tabScripts.contains(file) ? [] : tabCalls)
        let body = code.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        return banned.filter { body.range(of: $0, options: .regularExpression) != nil }
    }
}

/// What the extension is allowed to touch: only mail.google.com for mail, and the page is never driven.
@Suite struct ExtensionPolicyTests {
    private func contentScripts() throws -> [[String: Any]] {
        let data = try Data(contentsOf: ExtensionFiles.folder.appending(path: "manifest.json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(manifest["content_scripts"] as? [[String: Any]])
    }

    private func entry(running script: String) throws -> [String: Any] {
        try #require(try contentScripts().first { ($0["js"] as? [String])?.contains(script) == true })
    }

    @Test func theMailScriptsMatchOnlyMailGoogleCom() throws {
        let mail = try entry(running: "mail/watch.js")
        #expect(mail["matches"] as? [String] == ["https://mail.google.com/*"])
        #expect(
            (mail["js"] as? [String])?.allSatisfy { $0.hasPrefix("mail/") || $0.hasPrefix("read/") } == true,
            "page-text code never runs in the mail entry")
        for other in try contentScripts() where (other["js"] as? [String])?.contains("mail/watch.js") != true {
            #expect(
                (other["js"] as? [String])?.contains { $0.hasPrefix("mail/") } == false,
                "mail code is in no other entry")
        }
    }

    @Test func pageTextLeavesTheMailAndWhatsAppWebClients() throws {
        let pageText = try entry(running: "content.js")
        let excluded = Set(pageText["exclude_matches"] as? [String] ?? [])
        #expect(excluded == ["https://mail.google.com/*", "https://web.whatsapp.com/*"])
        for other in try contentScripts() where (other["js"] as? [String])?.contains("content.js") != true {
            #expect((other["exclude_matches"] as? [String]) == nil)
        }
        let runsOnWhatsAppWeb = try contentScripts().contains {
            ($0["matches"] as? [String])?.contains("https://web.whatsapp.com/*") == true
        }
        #expect(!runsOnWhatsAppWeb, "no script runs on WhatsApp Web")
    }

    @Test func noShippedScriptDispatchesAnEventOrChangesThePage() throws {
        let scripts = try ExtensionFiles.scripts()
        let shipped: Set = [
            "content.js", "mail/watch.js", "background.js", "background/host.js", "background/driver.js",
        ]
        #expect(Set(scripts.keys).isSuperset(of: shipped))
        for (name, code) in scripts { #expect(ExtensionFiles.drivingCalls(in: code, file: name).isEmpty, "\(name)") }
    }

    @Test func noScriptCanBeSentOrRunInATabAndNoCommandComesFromAPage() throws {
        let scripts = try ExtensionFiles.scripts()
        let background = try #require(scripts["background.js"])
        #expect(background.contains("onCommand: driver.handle"), "the driver is reached by the host port")
        let onPageMessage = try #require(background.components(separatedBy: "chrome.runtime.onMessage").last)
        #expect(!onPageMessage.contains("driver"), "a message from a page never reaches the driver")
        let driver = try #require(scripts["background/driver.js"])
        let sentToTabs = driver.matches(of: #/tabs\.sendMessage\([^)]*\)/#).map { String($0.output) }
        #expect(sentToTabs == [#"tabs.sendMessage(tab, { driver: "read" })"#], "the only message a tab gets is read")
        let listeners = scripts["content.js"]?.components(separatedBy: "chrome.runtime.onMessage.addListener")
        #expect(listeners?.count == 2, "one listener, for read")
    }

    @Test func theCheckFlagsEachWayToDriveThePage() {
        let planted = [
            "button.dispatchEvent(new MouseEvent('click'))", "message.click()", "key = new KeyboardEvent('keydown')",
            "input.focus()", "node.textContent = 'x'", "document.body.appendChild(node)", "node.style.color = 'red'",
            "chrome.scripting.executeScript({})", "window.postMessage(1, '*')", "document.execCommand('copy')",
            "chrome.debugger.attach({ tabId }, '1.3')", "chrome.tabs.create({ url })", "tabs.remove(id)",
        ]
        for line in planted {
            #expect(!ExtensionFiles.drivingCalls(in: line, file: "mail/watch.js").isEmpty, "\(line)")
        }
        let notForTheDriver = [
            "tabs.update(id, { url })", "tabs.reload(id)", "tabs.executeScript(id, {})", "chrome.debugger.attach()",
        ]
        for line in notForTheDriver {
            #expect(!ExtensionFiles.drivingCalls(in: line, file: "background/driver.js").isEmpty, "\(line)")
        }
        let open = "tabs.create({ url, active: false })"
        #expect(ExtensionFiles.drivingCalls(in: open, file: "background/driver.js").isEmpty)
        #expect(ExtensionFiles.drivingCalls(in: "tabs: chrome.tabs,", file: "background.js").isEmpty)
        #expect(ExtensionFiles.drivingCalls(in: "// button.click()\nconst x = a.textContent;", file: "x.js").isEmpty)
        #expect(ExtensionFiles.drivingCalls(in: "port.postMessage(m)", file: "background.js").isEmpty)
    }
}

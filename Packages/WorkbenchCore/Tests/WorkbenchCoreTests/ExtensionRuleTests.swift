import Foundation
import Testing

extension ExtensionFiles {
    /// The code lines of a script: whole-line comments left out.
    static func code(_ text: String) -> String {
        text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// Ways to find a page part by its class name: a class property, a class method, a class selector (a dot, then a
    /// name, inside the text given to a query method) or an attribute selector on the class attribute.
    static func classNameUses(in code: String) -> [String] {
        let direct = [#"\bclassName\b"#, #"\bclassList\b"#, #"getElementsByClassName"#, #"\[\s*class\b"#]
        let queryText = #"(?:querySelector(?:All)?|closest|matches)\(\s*(?:"([^"]*)"|'([^']*)'|`([^`]*)`)"#
        let selectors = code.matches(of: try! Regex(queryText)).map { match in
            (1...3).compactMap { match.output[$0].substring }.map(String.init).first ?? ""
        }
        let hits = direct.filter { code.range(of: $0, options: .regularExpression) != nil }
        return hits + selectors.filter { $0.range(of: #"\.[A-Za-z_-]"#, options: .regularExpression) != nil }
    }

    /// Names of sites the generic reader must not know.
    static let siteNames = [
        "gmail", "slack", "linkedin", "whatsapp", "outlook", "notion", "salesforce", "hubspot", "google", "github",
        "twitter", "facebook",
    ]

    /// The scripts that make up the generic reader. They hold no site name and no record.
    static let genericReader = ["read/generic.js", "read/interpret.js", "read/page.js"]

    static func siteNameUses(in code: String) -> [String] {
        siteNames.filter { code.range(of: $0, options: [.caseInsensitive]) != nil }
    }
}

/// What the extension is allowed to know about a page: no class name anywhere, and no site name in the generic reader.
@Suite struct ExtensionReaderRuleTests {
    @Test func noShippedScriptSelectsAPagePartByClassName() throws {
        let scripts = try ExtensionFiles.scripts()
        #expect(scripts.count >= 10, "the scan reads the shipped scripts")
        for (name, text) in scripts {
            #expect(ExtensionFiles.classNameUses(in: ExtensionFiles.code(text)).isEmpty, "\(name) uses a class name")
        }
    }

    @Test func theClassNameCheckFlagsEachWayToUseAClassName() {
        let planted = [
            #"document.querySelector("div.adn")"#, #"root.querySelectorAll('.a3s')"#, "node.className",
            "node.classList",
            #"document.getElementsByClassName("hP")"#, #"document.querySelector("[class~=hP]")"#,
            #"item.closest("li.row")"#,
        ]
        for line in planted { #expect(!ExtensionFiles.classNameUses(in: line).isEmpty, "\(line)") }
        let allowed = [
            #"document.querySelector("[data-message-id]")"#, #"root.querySelectorAll("h1,h2,[role='heading']")"#,
            #"const file = "mail/deck.js";"#, "// the .a3s names live elsewhere",
        ]
        for line in allowed { #expect(ExtensionFiles.classNameUses(in: ExtensionFiles.code(line)).isEmpty, "\(line)") }
    }

    @Test func theGenericReaderNamesNoSite() throws {
        let scripts = try ExtensionFiles.scripts()
        #expect(Set(scripts.keys).isSuperset(of: ExtensionFiles.genericReader))
        for name in ExtensionFiles.genericReader {
            #expect(ExtensionFiles.siteNameUses(in: try #require(scripts[name])).isEmpty, "\(name) names a site")
        }
        let records = try #require(scripts["read/records.js"])
        #expect(!ExtensionFiles.siteNameUses(in: records).isEmpty, "the records are where sites are named")
    }

    @Test func theSiteNameCheckFlagsANamedSite() {
        for line in ["if (host === 'mail.google.com')", "const isSlack = true", "// Gmail only", "LinkedIn feed"] {
            #expect(!ExtensionFiles.siteNameUses(in: line).isEmpty, "\(line)")
        }
        #expect(ExtensionFiles.siteNameUses(in: "const role = element.getAttribute('role');").isEmpty)
    }

    @Test func everyReaderScriptRunsInTheIsolatedWorldOnly() throws {
        let data = try Data(contentsOf: ExtensionFiles.folder.appending(path: "manifest.json"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for entry in try #require(manifest["content_scripts"] as? [[String: Any]]) {
            #expect(
                entry["world"] == nil || entry["world"] as? String == "ISOLATED", "no script runs in the page's world")
        }
        let scripts = try ExtensionFiles.scripts()
        for (name, text) in scripts {
            let mainWorld = text.range(of: #"world["']?\s*:\s*["']MAIN"#, options: .regularExpression)
            #expect(mainWorld == nil, "\(name) does not ask for the page's own world")
        }
    }
}

/// The plumbing: every frame, one native port, single-page apps.
@Suite struct ExtensionPlumbingRuleTests {
    private func manifest() throws -> [String: Any] {
        let data = try Data(contentsOf: ExtensionFiles.folder.appending(path: "manifest.json"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func entry(running script: String) throws -> [String: Any] {
        let entries = try #require(manifest()["content_scripts"] as? [[String: Any]])
        return try #require(entries.first { ($0["js"] as? [String])?.contains(script) == true })
    }

    @Test func theGenericReaderRunsInEveryFrameAndTheMailReaderOnlyInTheTopFrame() throws {
        #expect(try entry(running: "content.js")["all_frames"] as? Bool == true)
        #expect(try entry(running: "mail/watch.js")["all_frames"] as? Bool != true, "mail is read once, from the tab")
    }

    @Test func theShippedCodeNeverStartsOneHostProcessPerRead() throws {
        let scripts = try ExtensionFiles.scripts()
        for (name, text) in scripts {
            #expect(!ExtensionFiles.code(text).contains("sendNativeMessage"), "\(name) starts a host per message")
        }
        let openers = scripts.filter { ExtensionFiles.code($0.value).contains("connectNative") }.keys
        #expect(Array(openers) == ["background.js"], "one place opens the one port")
    }

    @Test func theServiceWorkerListensForSinglePageNavigationAndTheReaderForPageChanges() throws {
        let scripts = try ExtensionFiles.scripts()
        let rereads = try #require(scripts["background/rereads.js"])
        for event in ["onHistoryStateUpdated", "onReferenceFragmentUpdated"] {
            #expect(rereads.contains("webNavigation.\(event)") || rereads.contains(event), "no \(event) listener")
        }
        let background = try #require(scripts["background.js"])
        #expect(background.contains("rereadOnNavigation(chrome.webNavigation"))
        let permissions = ["nativeMessaging", "storage", "tabGroups", "webNavigation"]
        #expect(try manifest()["permissions"] as? [String] == permissions)
        let content = try #require(scripts["content.js"])
        #expect(content.contains("MutationObserver") && content.contains("reread"))
        #expect(try #require(manifest()["background"] as? [String: String])["type"] == "module")
    }
}

/// The browser is named by the app from the process tree. The extension never guesses it.
@Suite struct ExtensionBrowserRuleTests {
    @Test func noShippedScriptGuessesTheBrowser() throws {
        let guesses = [
            #"userAgentData"#, #"navigator\.brave"#, #"\bbrands\b"#,
            #"com\.[a-z]+\.[A-Za-z.]*(Browser|Chrome|edgemac)"#,
        ]
        for (name, text) in try ExtensionFiles.scripts() {
            for pattern in guesses {
                let found = ExtensionFiles.code(text).range(of: pattern, options: .regularExpression)
                #expect(found == nil, "\(name) guesses the browser: \(pattern)")
            }
        }
    }
}

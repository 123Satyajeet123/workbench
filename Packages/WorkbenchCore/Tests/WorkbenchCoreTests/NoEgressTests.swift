import Foundation
import Testing

enum EgressScan {
    static let bannedPatterns = [
        #"sentient-os\.ai"#, #"workers\.dev"#, #"supabase\.co"#, #"sentry\.io"#, #"getsentry"#,
        #"\bSentrySDK\b"#, #"telemetrydeck\.com"#, #"TelemetryDeck/SwiftSDK"#, #"\bTelemetryDeck\.(signal|initialize)"#,
        #"elevenlabs\.io"#, #"\bappcast\b"#, #"sparkle-project"#, #"\bSPU[A-Z][A-Za-z]+"#, #"composio\.dev"#,
        #"(?m)^\s*import\s+(Sentry|Sparkle|TelemetryDeck)\b"#,
    ]

    static let networkSymbolPatterns = [
        #"\bURLSession\w*"#, #"\bURLRequest\b"#, #"\bNSURLConnection\b"#, #"\bURLProtocol\b"#,
        #"\bNW(Connection|Listener|Endpoint)\b"#,
        #"(?m)^\s*import\s+Network\b"#, #"\bCFNetwork\b"#, #"\bCFHTTP\w*"#, #"\bCFSocket\w*"#, #"\bgetaddrinfo\b"#,
        #"\bWKWebView\b"#,
    ]

    static func networkSymbolHits(in text: String) -> [String] {
        networkSymbolPatterns.filter { text.range(of: $0, options: .regularExpression) != nil }
    }

    static let allowedHosts: Set<String> = ["mail.google.com", "api.search.brave.com", "api.exa.ai", "my.telegram.org"]

    static let webFolder = "/Sources/WebResearch/"
    static let webTransportFile = "WebTransport.swift"
    static let webGuards = ["grant.kind == .web", "grant.expiresAt > Date()"]

    static let telegramFile = "Packages/BaseKit/Sources/TelegramReader/TDLibTelegram.swift"
    static let telegramGuard = "try TelegramGate.check(policy)"
    static let telegramImport = #"(?m)^\s*(@preconcurrency\s+)?import\s+TDLib"#

    static func bannedHits(in text: String) -> [String] {
        bannedPatterns.filter { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    static func unexpectedHosts(in text: String) -> [String] {
        text.matches(of: #/https?:\/\/([A-Za-z0-9.-]+)/#).map { String($0.1).lowercased() }
            .filter { !allowedHosts.contains($0) && !isReservedExample($0) }
    }

    static func isReservedExample(_ host: String) -> Bool {
        host == "example" || host.hasSuffix(".example")
    }

    static func shippedFiles(repo: URL) -> [URL] {
        let fileManager = FileManager.default
        let roots = ["Workbench", "Workbench.xcodeproj", "Workbench.entitlements", "Extension"].map {
            repo.appending(path: $0)
        }
        let packages =
            ((try? fileManager.contentsOfDirectory(
                at: repo.appending(path: "Packages"), includingPropertiesForKeys: nil))
            ?? []).map { $0.appending(path: "Sources") }
        return (roots + packages).flatMap { root -> [URL] in
            guard let walker = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else { return [root] }
            return walker.compactMap { $0 as? URL }.filter {
                ["swift", "plist", "json", "entitlements", "pbxproj", "js"].contains($0.pathExtension)
                    && !$0.pathComponents.contains("xcuserdata")
            }
        }
    }
}

struct NoEgressTests {
    static let repo = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func shippedSourcesNameNoBannedOrUnexpectedHost() throws {
        let files = EgressScan.shippedFiles(repo: Self.repo)
        let names = Set(files.map(\.lastPathComponent))
        #expect(names.isSuperset(of: ["Store.swift", "AgentRunner.swift", "HelperContent.swift", "project.pbxproj"]))
        var findings: [String] = []
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let name = file.path.replacingOccurrences(of: Self.repo.path + "/", with: "")
            findings += EgressScan.bannedHits(in: text).map { "\(name): banned \($0)" }
            findings += EgressScan.unexpectedHosts(in: text).map { "\(name): host \($0)" }
        }
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    @Test func theBrowserExtensionSendsOnlyToTheLocalHost() throws {
        let folder = Self.repo.appending(path: "Extension")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: "manifest.json")))
        let keys = try #require(manifest as? [String: Any])
        #expect(keys["permissions"] as? [String] == ["nativeMessaging"])
        #expect(keys["host_permissions"] == nil && keys["optional_host_permissions"] == nil)
        #expect(keys["incognito"] as? String == "not_allowed")
        for (name, code) in try ExtensionFiles.scripts() {
            let network = #/\b(XMLHttpRequest|WebSocket|EventSource|sendBeacon|importScripts)\b|\bimport\(/#
            #expect(code.firstMatch(of: network) == nil, "\(name) has a network call")
            let fetch = #/\bfetch\(/#
            #expect(name == "mail/deck.js" || code.firstMatch(of: fetch) == nil, "\(name) calls fetch")
        }
        let deck = try #require(try ExtensionFiles.scripts()["mail/deck.js"])
        #expect(deck.components(separatedBy: "fetch(").count == 2, "one fetch call")
        for guardText in ["sameOrigin(address, pageOrigin)", #"credentials: "same-origin""#, #"redirect: "error""#] {
            #expect(deck.contains(guardText), "the attachment fetch lost \(guardText)")
        }
    }

    @Test func noPackageUsesANetworkApi() throws {
        var seen: Set<String> = []
        var findings: [String] = []
        for package in ["WorkbenchCore", "BaseKit", "WorkbenchUI"] {
            let sources = Self.repo.appending(path: "Packages/\(package)/Sources")
            let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            for case let file as URL in walker where file.pathExtension == "swift" {
                seen.insert(file.lastPathComponent)
                guard !file.path.contains(EgressScan.webFolder) else { continue }
                let text = try String(contentsOf: file, encoding: .utf8)
                findings += EgressScan.networkSymbolHits(in: text).map { "\(file.lastPathComponent): \($0)" }
            }
        }
        #expect(seen.isSuperset(of: ["Store.swift", "AgentRunner.swift", "HelperContent.swift"]))
        #expect(findings.isEmpty, "\(findings.joined(separator: "\n"))")
    }

    @Test func onlyTheWebTransportOpensAConnectionAndItChecksTheWebGrant() throws {
        let folder = Self.repo.appending(path: "Packages/BaseKit/Sources/WebResearch")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var opening: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.range(of: #"\bURLSession\b"#, options: .regularExpression) != nil {
                opening.append(file.lastPathComponent)
            }
            if file.lastPathComponent == EgressScan.webTransportFile {
                for guardText in EgressScan.webGuards { #expect(text.contains(guardText), "lost \(guardText)") }
            }
        }
        #expect(opening == [EgressScan.webTransportFile])
    }

    @Test func onlyTheTelegramReaderTalksToTelegramAndOnlyWithTelegramSwitchedOn() throws {
        var importing: [String] = []
        for package in ["WorkbenchCore", "BaseKit", "WorkbenchUI"] {
            let sources = Self.repo.appending(path: "Packages/\(package)/Sources")
            let walker = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            for case let file as URL in walker where file.pathExtension == "swift" {
                let text = try String(contentsOf: file, encoding: .utf8)
                if text.range(of: EgressScan.telegramImport, options: .regularExpression) != nil {
                    importing.append(file.path.replacingOccurrences(of: Self.repo.path + "/", with: ""))
                }
            }
        }
        #expect(importing == [EgressScan.telegramFile])
        let connection = try String(contentsOf: Self.repo.appending(path: EgressScan.telegramFile), encoding: .utf8)
        #expect(connection.contains(EgressScan.telegramGuard), "Telegram connects without checking its switch")
    }

    @Test func plantedNetworkSymbolIsCaughtAndPlainCodeIsNot() {
        #expect(
            !EgressScan.networkSymbolHits(in: "let (data, _) = try await URLSession.shared.data(from: url)").isEmpty)
        #expect(!EgressScan.networkSymbolHits(in: "import Network\nlet c = NWConnection(to: e, using: .tcp)").isEmpty)
        #expect(
            EgressScan.networkSymbolHits(in: "let parts = URLComponents(string: text)\nlet file = URL(filePath: path)")
                .isEmpty)
    }
}

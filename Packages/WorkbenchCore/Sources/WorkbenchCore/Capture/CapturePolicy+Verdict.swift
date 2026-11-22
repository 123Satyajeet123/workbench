import Foundation

public enum CaptureVerdict: Sendable, Equatable {
    case keep(CaptureGrant)
    case hide(CaptureGrant)
    case stop
}

extension CapturePolicy {
    public func verdict(for snapshot: ScreenSnapshot, at now: Date) -> CaptureVerdict {
        switch authorize(CaptureRequest(kind: .screen, label: snapshot.bundleID), at: now) {
        case .allow(let grant): hidesScreen(snapshot) ? .hide(grant) : .keep(grant)
        case .deny(.labelDenied), .deny(.labelNotAllowed): bare(.screen, at: now)
        case .deny, .confirm: .stop
        }
    }

    public func verdict(forFile path: String, at now: Date) -> CaptureVerdict {
        switch authorize(CaptureRequest(kind: .files, label: path), at: now) {
        case .allow(let grant): Self.hidesFile(path) ? .hide(grant) : .keep(grant)
        case .deny(.labelDenied), .deny(.labelNotAllowed): bare(.files, at: now)
        case .deny, .confirm: .stop
        }
    }

    private func bare(_ kind: SourceKind, at now: Date) -> CaptureVerdict {
        authorize(CaptureRequest(kind: kind), at: now).grant.map(CaptureVerdict.hide) ?? .stop
    }

    private func hidesScreen(_ snapshot: ScreenSnapshot) -> Bool {
        let title = snapshot.title.lowercased()
        let browserWithoutAddress = Self.browserBundleIDs.contains(snapshot.bundleID) && snapshot.document.isEmpty
        return snapshot.secureFocus || browserWithoutAddress || Self.privateBundleIDs.contains(snapshot.bundleID)
            || (Self.privateWords + Self.privateWindowMarkers).contains { title.contains($0) }
            || Self.isSite(snapshot.document, in: Self.privateDomains.union(denyList[.screen] ?? []))
    }

    private static func hidesFile(_ path: String) -> Bool {
        let url = URL(filePath: path)
        let name = url.lastPathComponent
        return privateWords.contains { name.lowercased().contains($0) } || noiseNames.contains(name)
            || noiseSuffixes.contains { name.hasSuffix($0) }
            || url.pathComponents.contains { noiseFolders.contains($0) }
    }

    public static func isSite(_ document: String, in domains: Set<String>) -> Bool {
        guard let host = host(of: document) else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    public static func host(of document: String) -> String? {
        guard !document.isEmpty, !document.hasPrefix("file:") else { return nil }
        let withScheme = document.contains("://") ? document : "https://" + document
        guard var host = URLComponents(string: withScheme)?.host?.lowercased() else { return nil }
        while host.hasSuffix(".") { host.removeLast() }
        return host
    }

    public static let browserBundleIDs: Set<String> = [
        "com.brave.Browser", "com.google.Chrome", "company.thebrowser.Browser", "com.apple.Safari",
        "com.microsoft.edgemac", "org.mozilla.firefox",
    ]

    static let privateBundleIDs: Set<String> = [
        "com.1password.1password", "com.agilebits.onepassword7", "com.agilebits.onepassword-osx",
        "com.bitwarden.desktop", "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal", "org.keepassxc.keepassxc",
        "com.apple.Passwords", "com.apple.keychainaccess", "com.nordsec.nordpass", "me.proton.pass.electron",
        "com.apple.Health",
    ]

    public static let privateDomains: Set<String> = [
        "hdfcbank.com", "icicibank.com", "onlinesbi.sbi", "sbi.co.in", "axisbank.com", "kotak.com", "bankofbaroda.in",
        "yesbank.in", "idfcfirstbank.com", "chase.com", "bankofamerica.com", "wellsfargo.com", "citi.com", "hsbc.com",
        "americanexpress.com", "paypal.com", "wise.com", "kite.zerodha.com", "practo.com", "1mg.com", "pharmeasy.in",
        "apollo247.com", "mychart.org", "zocdoc.com", "1password.com", "bitwarden.com", "lastpass.com",
        "dashlane.com", "keepersecurity.com",
    ]

    private static let privateWords = ["password"]
    private static let privateWindowMarkers = [
        "private browsing", "incognito", "inprivate", "private window", "- private",
    ]
    private static let noiseFolders: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", ".swiftpm", "Pods", ".venv", "__pycache__", ".next",
        ".Trash", "Library",
    ]
    private static let noiseNames: Set<String> = [".DS_Store"]
    private static let noiseSuffixes = ["~", ".swp", ".tmp", ".lock", ".sqlite-wal", ".sqlite-shm"]
}

import Foundation

/// What the policy says about one thing a sensor saw. `hide` drops that thing only and grants the bare markers
/// (idle, skipped); `stop` drops all capture.
public enum CaptureVerdict: Sendable, Equatable {
    case keep(CaptureGrant)
    case hide(CaptureGrant)
    case stop
}

/// What the policy says about an app before anything of it is read. Only bundle-id metadata went into it.
public enum ReadAdmission: Sendable, Equatable {
    /// The window may be read. The grant is the permission to do it.
    case read(CaptureGrant)
    /// The app may not be read. The grant lets the bare marker (skipped) be written.
    case skip(CaptureGrant)
    case stop
}

extension CapturePolicy {
    /// The gate every screen read passes first: the front app's bundle id, before any Accessibility call. An app with
    /// no bundle id has no label to check, so it is never read.
    public func admission(ofApp bundleID: String, at now: Date) -> ReadAdmission {
        guard !bundleID.isEmpty else { return bare(.screen, at: now) }
        switch authorize(CaptureRequest(kind: .screen, label: bundleID), at: now) {
        case .allow(let grant): return Self.privateBundleIDs.contains(bundleID) ? .skip(grant) : .read(grant)
        case .deny(.labelDenied), .deny(.labelNotAllowed): return bare(.screen, at: now)
        case .deny, .confirm: return .stop
        }
    }

    /// The admission, then what the window's own title, address and focus say: a private window is hidden.
    public func verdict(for snapshot: ScreenSnapshot, at now: Date) -> CaptureVerdict {
        switch admission(ofApp: snapshot.bundleID, at: now) {
        case .stop: .stop
        case .skip(let grant): .hide(grant)
        case .read(let grant): hidesContent(of: snapshot) ? .hide(grant) : .keep(grant)
        }
    }

    private func bare(_ kind: SourceKind, at now: Date) -> ReadAdmission {
        authorize(CaptureRequest(kind: kind), at: now).grant.map(ReadAdmission.skip) ?? .stop
    }

    private func hidesContent(of snapshot: ScreenSnapshot) -> Bool {
        let title = snapshot.title.lowercased()
        let browserWithoutAddress = Self.browserBundleIDs.contains(snapshot.bundleID) && snapshot.document.isEmpty
        return snapshot.secureFocus || browserWithoutAddress
            || (Self.privateWords + Self.privateWindowMarkers).contains { title.contains($0) }
            || Self.isSite(snapshot.document, in: Self.privateDomains.union(denyList[.screen] ?? []))
    }

    /// The document's host is one of the domains or a subdomain of one. A trailing dot names the same host.
    public static func isSite(_ document: String, in domains: Set<String>) -> Bool {
        guard let host = host(of: document) else { return false }
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Address bars often drop the scheme ("example.com/path").
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
}

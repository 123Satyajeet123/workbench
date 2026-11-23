import Foundation

/// One page the driver is asked to open. The method is part of the request so that the gate states the rule: GET only.
public struct DriverRequest: Sendable, Equatable {
    public var url: URL
    public var method: String

    public init(url: URL, method: String = "GET") {
        self.url = url
        self.method = method
    }
}

public enum DriverRefusal: Equatable, Sendable, CustomStringConvertible {
    case notGET(String)
    case notWeb
    case hasCredentials
    case notPublicHost(String)
    case consent(DenyReason)
    case deniedSite(String)

    public var description: String {
        switch self {
        case .notGET(let method): "The browser driver only reads (GET). \(method) is not allowed."
        case .notWeb: "The browser driver opens only http and https addresses."
        case .hasCredentials: "An address with a user name or password in it is not opened."
        case .notPublicHost(let host): "\(host) is not a public web address, so it was not opened."
        case .consent(let reason): "Web reading is not allowed now (\(reason))."
        case .deniedSite(let host): "\(host) is on the list of sites Workbench does not read."
        }
    }
}

/// The deterministic gate before any command leaves the app. Page text never reaches it.
public struct DriverGate: Sendable {
    public var policy: CapturePolicy

    public init(policy: CapturePolicy) { self.policy = policy }

    /// Sites a machine never opens: the mail and chat clients, which page capture never keeps, and LinkedIn, which the
    /// founder ruled out.
    static let neverRead: Set<String> = [MailContext.site, WebPage.whatsAppWebHost, WebPage.linkedInHost]

    public func refusal(for request: DriverRequest, at now: Date) -> DriverRefusal? {
        guard request.method == "GET" else { return .notGET(request.method) }
        let url = request.url
        guard ["http", "https"].contains(url.scheme?.lowercased()), let host = url.host()?.lowercased() else {
            return .notWeb
        }
        guard url.user() == nil, url.password() == nil else { return .hasCredentials }
        guard Self.isPublic(host) else { return .notPublicHost(host) }
        if case .deny(let reason) = policy.authorize(CaptureRequest(kind: .web), at: now) { return .consent(reason) }
        let denied = CapturePolicy.privateDomains.union(Self.neverRead)
            .union(policy.denyList[.web] ?? []).union(policy.denyList[.screen] ?? [])
        return CapturePolicy.isSite(url.absoluteString, in: denied) ? .deniedSite(host) : nil
    }

    private static func isPublic(_ host: String) -> Bool {
        let isAddress = host.allSatisfy { $0.isNumber || $0 == "." } || host.contains(":")
        return host.contains(".") && !isAddress && !host.hasSuffix(".local") && !host.hasSuffix(".internal")
    }
}

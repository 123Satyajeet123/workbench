import Foundation

/// Why a source cannot read now, in a form the person can act on. Each case has one sentence.
public enum SourceProblem: Sendable, Equatable {
    case consentOff
    case ownerMissing
    case permissionMissing(HealthNeed.MacPermission)
    /// The source signs in only with an app key of the person's own, kept in the keychain.
    case keyMissing(HealthNeed.AppKey)
    /// The reader for this site found its page changed: the site's record is stale with the site.
    case siteStale(String)
    /// No browser Workbench works in is switched on, or none is known.
    case browserNotReady(String)

    public var sentence: String {
        switch self {
        case .consentOff: "Turned off in Settings › Capture."
        case .ownerMissing: "Workbench could not open the name it keeps for you in the Keychain."
        case .permissionMissing(.fullDiskAccess):
            "macOS has not given Workbench Full Disk Access. Turn it on in System Settings › Privacy & Security, then reopen Workbench."
        case .permissionMissing(.accessibility): "macOS has not given Workbench Accessibility access yet."
        case .keyMissing(.telegramApp): "Telegram needs its app key; add it on the machine's page."
        case .siteStale(let site): AdapterState.sentence(for: site)
        case .browserNotReady(let reason): reason
        }
    }
}

/// What must hold before a source can read. A descriptor lists its needs; health folds them over what the app knows.
public enum HealthNeed: Sendable, Equatable {
    /// The capture switch of the source's consent kind is on.
    case consent
    /// The app knows the person who uses this Mac.
    case owner
    /// macOS has given Workbench this permission.
    case permission(MacPermission)
    /// The person's own app key is in the keychain.
    case key(AppKey)
    /// A browser Workbench works in is known and switched on.
    case browser
    /// No reader of the sites in this scope reported a changed page.
    case readerCurrent(SiteScope)

    /// A permission macOS gives per app.
    public enum MacPermission: Sendable, Hashable { case fullDiskAccess, accessibility }

    /// A key the person adds on a machine's page.
    public enum AppKey: Sendable, Hashable { case telegramApp }

    /// Which sites a reader reports on: the mail site, or every other.
    public enum SiteScope: Sendable, Equatable {
        case mail, otherSites

        func contains(_ site: String) -> Bool { (site == AdapterState.mailSite) == (self == .mail) }
    }
}

/// One source and what stops it now. An empty `problems` means ready.
public struct SourceHealth: Sendable, Equatable, Identifiable {
    public let source: SourceDescriptor
    public let problems: [SourceProblem]

    public var id: String { source.key }
    public var isReady: Bool { problems.isEmpty }
    public var sentences: [String] { problems.map(\.sentence) }
}

/// What the app knows about its Mac and its consent when it asks for the health of every source.
public struct SourceHealthInputs: Sendable {
    public var policy: CapturePolicy
    /// The permissions macOS has given.
    public var permissions: Set<HealthNeed.MacPermission>
    public var ownerKnown: Bool
    /// The keys the person has put in the keychain.
    public var keys: Set<HealthNeed.AppKey>
    /// The sites whose reader reported a changed page, by name.
    public var staleSites: [String]
    /// The health of each browser on this Mac, from the policy.
    public var browsers: [BrowserHealth]

    public init(
        policy: CapturePolicy, permissions: Set<HealthNeed.MacPermission>, ownerKnown: Bool,
        keys: Set<HealthNeed.AppKey>, staleSites: [String], browsers: [BrowserHealth]
    ) {
        self.policy = policy
        self.permissions = permissions
        self.ownerKnown = ownerKnown
        self.keys = keys
        self.staleSites = staleSites
        self.browsers = browsers
    }
}

/// The one model of source health. Pure: it reads only its inputs.
public enum SourceHealthModel {
    public static func health(_ inputs: SourceHealthInputs) -> [SourceHealth] {
        SourceRegistry.withNeeds.map { source in
            SourceHealth(source: source, problems: source.needs.flatMap { problems(of: $0, for: source, inputs) })
        }
    }

    private static func problems(of need: HealthNeed, for source: SourceDescriptor, _ inputs: SourceHealthInputs)
        -> [SourceProblem]
    {
        switch need {
        case .consent: inputs.policy.isEnabled(source.consent) ? [] : [.consentOff]
        case .owner: inputs.ownerKnown ? [] : [.ownerMissing]
        case .permission(let permission):
            inputs.permissions.contains(permission) ? [] : [.permissionMissing(permission)]
        case .key(let key): inputs.keys.contains(key) ? [] : [.keyMissing(key)]
        case .browser: browser(inputs)
        case .readerCurrent(let scope): inputs.staleSites.filter(scope.contains).map(SourceProblem.siteStale)
        }
    }

    /// Page and mail text come only through a browser that is known and switched on. One working browser is enough.
    private static func browser(_ inputs: SourceHealthInputs) -> [SourceProblem] {
        guard !inputs.browsers.contains(where: \.isHealthy) else { return [] }
        let reason =
            inputs.browsers.compactMap(\.problem).first ?? "Workbench found no Chromium browser to read pages in."
        return [.browserNotReady(reason)]
    }
}

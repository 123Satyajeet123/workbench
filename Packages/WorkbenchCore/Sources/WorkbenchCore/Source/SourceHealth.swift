import Foundation

/// Why a source cannot read now, in a form the person can act on. Each case has one sentence.
public enum SourceProblem: Sendable, Equatable {
    case consentOff
    case fullDiskAccessMissing
    case ownerMissing
    case accessibilityMissing
    /// The reader for this site found its page changed: the site's record is stale with the site.
    case siteStale(String)
    /// No browser Workbench works in is switched on, or none is known.
    case browserNotReady(String)

    public var sentence: String {
        switch self {
        case .consentOff: "Turned off in Settings › Capture."
        case .fullDiskAccessMissing:
            "macOS has not given Workbench Full Disk Access. Turn it on in System Settings › Privacy & Security, then reopen Workbench."
        case .ownerMissing: "Workbench could not open the name it keeps for you in the Keychain."
        case .accessibilityMissing: "macOS has not given Workbench Accessibility access yet."
        case .siteStale(let site): AdapterState.sentence(for: site)
        case .browserNotReady(let reason): reason
        }
    }
}

/// One source and what stops it now. An empty `problems` means ready.
public struct SourceHealth: Sendable, Equatable, Identifiable {
    public enum Source: String, Sendable, CaseIterable {
        case whatsapp, mail, pages, screen

        public var name: String {
            switch self {
            case .whatsapp: "WhatsApp"
            case .mail: "Mail"
            case .pages: "Web pages"
            case .screen: "Screen"
            }
        }
    }

    public let source: Source
    public let problems: [SourceProblem]

    public var id: String { source.rawValue }
    public var isReady: Bool { problems.isEmpty }
    public var sentences: [String] { problems.map(\.sentence) }
}

/// What the app knows about its Mac and its consent when it asks for the health of every source.
public struct SourceHealthInputs: Sendable {
    public var policy: CapturePolicy
    public var fullDiskAccess: Bool
    public var ownerKnown: Bool
    public var accessibilityGranted: Bool
    /// The sites whose reader reported a changed page, by name.
    public var staleSites: [String]
    /// The health of each browser on this Mac, from the policy.
    public var browsers: [BrowserHealth]

    public init(
        policy: CapturePolicy, fullDiskAccess: Bool, ownerKnown: Bool, accessibilityGranted: Bool,
        staleSites: [String], browsers: [BrowserHealth]
    ) {
        self.policy = policy
        self.fullDiskAccess = fullDiskAccess
        self.ownerKnown = ownerKnown
        self.accessibilityGranted = accessibilityGranted
        self.staleSites = staleSites
        self.browsers = browsers
    }
}

/// The one model of source health. Pure: it reads only its inputs.
public enum SourceHealthModel {
    public static func health(_ inputs: SourceHealthInputs) -> [SourceHealth] {
        SourceHealth.Source.allCases.map { SourceHealth(source: $0, problems: problems(of: $0, inputs)) }
    }

    private static func problems(of source: SourceHealth.Source, _ inputs: SourceHealthInputs) -> [SourceProblem] {
        switch source {
        case .whatsapp:
            consent(.whatsapp, inputs) + (inputs.fullDiskAccess ? [] : [.fullDiskAccessMissing]) + owner(inputs)
        case .mail:
            consent(.mail, inputs) + owner(inputs) + browser(inputs)
                + stale(inputs) { $0 == AdapterState.mailSite }
        case .pages:
            consent(.screenText, inputs) + owner(inputs) + browser(inputs)
                + stale(inputs) { $0 != AdapterState.mailSite }
        case .screen:
            consent(.screen, inputs) + (inputs.accessibilityGranted ? [] : [.accessibilityMissing])
        }
    }

    private static func consent(_ kind: SourceKind, _ inputs: SourceHealthInputs) -> [SourceProblem] {
        inputs.policy.isEnabled(kind) ? [] : [.consentOff]
    }

    private static func owner(_ inputs: SourceHealthInputs) -> [SourceProblem] {
        inputs.ownerKnown ? [] : [.ownerMissing]
    }

    /// Page and mail text come only through a browser that is known and switched on. One working browser is enough.
    private static func browser(_ inputs: SourceHealthInputs) -> [SourceProblem] {
        guard !inputs.browsers.contains(where: \.isHealthy) else { return [] }
        let reason =
            inputs.browsers.compactMap(\.problem).first ?? "Workbench found no Chromium browser to read pages in."
        return [.browserNotReady(reason)]
    }

    private static func stale(_ inputs: SourceHealthInputs, where belongs: (String) -> Bool) -> [SourceProblem] {
        inputs.staleSites.filter(belongs).map(SourceProblem.siteStale)
    }
}

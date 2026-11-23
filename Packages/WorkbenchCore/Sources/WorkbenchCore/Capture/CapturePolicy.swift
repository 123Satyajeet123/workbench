import Foundation

/// What a reader asks before it reads. `label` is a chat, a sender or a domain.
public struct CaptureRequest: Sendable {
    public var kind: SourceKind
    public var label: String?
    /// A live recording of a call, as opposed to reading text that already exists.
    public var liveSession: Bool

    public init(kind: SourceKind, label: String? = nil, liveSession: Bool = false) {
        self.kind = kind
        self.label = label
        self.liveSession = liveSession
    }
}

/// Permission to read once. Only `CapturePolicy` can make one, so a reader cannot skip the check.
public struct CaptureGrant: Sendable, Equatable {
    public let kind: SourceKind
    public let label: String?
    public let expiresAt: Date

    fileprivate init(kind: SourceKind, label: String? = nil, expiresAt: Date) {
        self.kind = kind
        self.label = label
        self.expiresAt = expiresAt
    }
}

extension CaptureGrant {
    /// The grant of the person's own act, such as adding a file to a deal. The act is the consent, so no switch stands
    /// behind it. Nil for a kind that needs the policy.
    public static func byHand(_ kind: SourceKind, label: String, at now: Date) -> CaptureGrant? {
        kind.isByHand
            ? CaptureGrant(kind: kind, label: label, expiresAt: now.addingTimeInterval(CapturePolicy.grantLifetime))
            : nil
    }
}

public enum DenyReason: Sendable, Equatable {
    case captureOff, paused, privateMode, sourceSwitchedOff, labelDenied, labelNotAllowed
}

/// A live recording while private mode is on. The founder must say yes; only then does a grant exist.
public struct PendingConfirmation: Sendable {
    public let why: String
    let kind: SourceKind
    let label: String?
    let grantLifetime: TimeInterval

    public func confirmed(at now: Date) -> CaptureGrant {
        CaptureGrant(kind: kind, label: label, expiresAt: now.addingTimeInterval(grantLifetime))
    }
}

public enum CaptureDecision: Sendable {
    case allow(CaptureGrant)
    case deny(DenyReason)
    case confirm(PendingConfirmation)

    public var grant: CaptureGrant? { if case .allow(let grant) = self { grant } else { nil } }
}

/// The one capture setting. The settings screen, the menu bar and every reader read this value.
public struct CapturePolicy: Codable, Sendable, Equatable {
    public enum Mode: Codable, Sendable, Equatable {
        case on
        case paused(until: Date)
        case privateMode(until: Date)
        case off
    }

    public static let grantLifetime: TimeInterval = 300

    public var mode: Mode
    /// A missing entry means off.
    public var switches: [SourceKind: Bool]
    public var denyList: [SourceKind: Set<String>]
    /// The labels a source may read. Nil means every label, except for a source that needs a list.
    public var allowList: [SourceKind: Set<String>]
    /// The browsers the person said yes to, as bundle id to name. Pages and mail come only from these.
    public var browsers: [String: String]

    public init(
        mode: Mode = .on, switches: [SourceKind: Bool] = [:], denyList: [SourceKind: Set<String>] = [:],
        allowList: [SourceKind: Set<String>] = [:], browsers: [String: String] = [:]
    ) {
        self.mode = mode
        self.switches = switches
        self.denyList = denyList
        self.allowList = allowList
        self.browsers = browsers
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        mode = try values.decode(Mode.self, forKey: .mode)
        switches = try values.decode([SourceKind: Bool].self, forKey: .switches)
        denyList = try values.decode([SourceKind: Set<String>].self, forKey: .denyList)
        allowList = try values.decode([SourceKind: Set<String>].self, forKey: .allowList)
        browsers = try values.decodeIfPresent([String: String].self, forKey: .browsers) ?? [:]
    }

    /// Captured data older than this is deleted: it is how far back anything reads.
    public static let retention: TimeInterval = 30 * 86_400

    /// Sources that read other people's words read only the labels listed: one chat or one mail label, never all of them.
    public static let needsAllowList: Set<SourceKind> = [.whatsapp, .telegram, .mail]

    public func isEnabled(_ kind: SourceKind) -> Bool { switches[kind] ?? false }

    public func isEnabled(browser bundleID: String) -> Bool { browsers[bundleID] != nil }

    /// The labels (chats, mail labels) of `kind` this policy allows and `other` does not, sorted.
    public func withdrawn(_ kind: SourceKind, in other: CapturePolicy) -> [String] {
        (allowList[kind] ?? []).subtracting(other.allowList[kind] ?? []).sorted()
    }

    public func authorize(_ request: CaptureRequest, at now: Date) -> CaptureDecision {
        if request.kind == .note { return authorizeNote(request, at: now) }
        if mode == .off { return .deny(.captureOff) }
        guard isEnabled(request.kind) else { return .deny(.sourceSwitchedOff) }
        if let label = request.label, denyList[request.kind]?.contains(label) == true {
            return .deny(.labelDenied)
        }
        if let allowed = allowList[request.kind] ?? (Self.needsAllowList.contains(request.kind) ? [] : nil),
            request.label.map({ allowed.contains($0) }) != true
        {
            return .deny(.labelNotAllowed)
        }
        switch mode {
        case .paused(let until) where now < until: return .deny(.paused)
        case .privateMode(let until) where now < until:
            guard request.liveSession else { return .deny(.privateMode) }
            return .confirm(
                PendingConfirmation(
                    why: "Private mode is on. Record this call anyway?", kind: request.kind, label: request.label,
                    grantLifetime: Self.grantLifetime))
        case .on, .off, .paused, .privateMode:
            return .allow(
                CaptureGrant(
                    kind: request.kind, label: request.label, expiresAt: now.addingTimeInterval(Self.grantLifetime)))
        }
    }
}

extension CapturePolicy {
    /// A note is what the person writes, not what a sensor reads: only a project the person put on the deny list stops it.
    fileprivate func authorizeNote(_ request: CaptureRequest, at now: Date) -> CaptureDecision {
        if let label = request.label, denyList[.note]?.contains(label) == true { return .deny(.labelDenied) }
        return .allow(
            CaptureGrant(kind: .note, label: request.label, expiresAt: now.addingTimeInterval(Self.grantLifetime)))
    }
}

public enum CaptureStatus: Sendable, Equatable {
    case capturing, paused, privateMode, off, needsPermission
}

extension CapturePolicy {
    /// What the menu bar shows: whether the clock, the switches and the Mac's permission let capture run now.
    public func status(accessibilityGranted: Bool, at now: Date) -> CaptureStatus {
        switch mode {
        case .off: return .off
        case .paused(let until) where now < until: return .paused
        case .privateMode(let until) where now < until: return .privateMode
        case .on, .paused, .privateMode: break
        }
        guard isEnabled(.screen) else { return .off }
        return isEnabled(.screen) && !accessibilityGranted ? .needsPermission : .capturing
    }
}

/// A reader's `init` takes one of these, with no default. The store keeps the policy as the latest consent event.
public protocol CapturePolicyProvider: Sendable {
    func currentPolicy() async throws -> CapturePolicy
}

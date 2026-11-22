import Foundation

public struct CaptureRequest: Sendable {
    public var kind: SourceKind
    public var label: String?
    public var liveSession: Bool

    public init(kind: SourceKind, label: String? = nil, liveSession: Bool = false) {
        self.kind = kind
        self.label = label
        self.liveSession = liveSession
    }
}

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

public enum DenyReason: Sendable, Equatable {
    case captureOff, paused, privateMode, sourceSwitchedOff, labelDenied, labelNotAllowed
}

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

public struct CapturePolicy: Codable, Sendable, Equatable {
    public enum Mode: Codable, Sendable, Equatable {
        case on
        case paused(until: Date)
        case privateMode(until: Date)
        case off
    }

    public static let grantLifetime: TimeInterval = 300

    public var mode: Mode
    public var switches: [SourceKind: Bool]
    public var denyList: [SourceKind: Set<String>]
    public var allowList: [SourceKind: Set<String>]

    public init(
        mode: Mode = .on, switches: [SourceKind: Bool] = [:], denyList: [SourceKind: Set<String>] = [:],
        allowList: [SourceKind: Set<String>] = [:]
    ) {
        self.mode = mode
        self.switches = switches
        self.denyList = denyList
        self.allowList = allowList
    }

    public static let needsAllowList: Set<SourceKind> = [.whatsapp, .mail]

    public func isEnabled(_ kind: SourceKind) -> Bool { switches[kind] ?? false }

    public func authorize(_ request: CaptureRequest, at now: Date) -> CaptureDecision {
        if mode == .off { return .deny(.captureOff) }
        guard isEnabled(request.kind) else { return .deny(.sourceSwitchedOff) }
        if let label = request.label, matches(label, in: denyList[request.kind], kind: request.kind) {
            return .deny(.labelDenied)
        }
        if let allowed = allowList[request.kind] ?? (Self.needsAllowList.contains(request.kind) ? [] : nil),
            request.label.map({ matches($0, in: allowed, kind: request.kind) }) != true
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

    private func matches(_ label: String, in entries: Set<String>?, kind: SourceKind) -> Bool {
        guard let entries else { return false }
        guard kind == .files else { return entries.contains(label) }
        return entries.contains { label == $0 || label.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}

public enum CaptureStatus: Sendable, Equatable {
    case capturing, paused, privateMode, off, needsPermission
}

extension CapturePolicy {
    public func status(accessibilityGranted: Bool, at now: Date) -> CaptureStatus {
        switch mode {
        case .off: return .off
        case .paused(let until) where now < until: return .paused
        case .privateMode(let until) where now < until: return .privateMode
        case .on, .paused, .privateMode: break
        }
        guard isEnabled(.screen) || isEnabled(.files) else { return .off }
        return isEnabled(.screen) && !accessibilityGranted ? .needsPermission : .capturing
    }
}

public protocol CapturePolicyProvider: Sendable {
    func currentPolicy() async throws -> CapturePolicy
}

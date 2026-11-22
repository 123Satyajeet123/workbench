import Foundation
import Kernel
import LocalSources
import Observation
import WorkbenchCore

/// The one capture service. It reads the sensors, asks the policy about everything it sees, and writes what the
/// engine keeps. The UI starts it, stops it and shows its state.
@MainActor @Observable
public final class CaptureService {
    public static let interval: Duration = .seconds(2)

    public private(set) var policy: CapturePolicy
    public private(set) var status: CaptureStatus
    /// The call being recorded now, if any.
    public private(set) var call: Recording?
    /// Apps playing sound now, refreshed every tick: the calls that can be recorded.
    public private(set) var playingApps: [AudioApp] = []
    /// The last write or delete that failed in the background, in plain words. Nil after the next one succeeds.
    public private(set) var problem: String?

    @ObservationIgnored private let ownerResult: Result<PersonID, any Error>
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let loop: CaptureLoop
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var whatsAppWatch: WhatsAppIngestWatch?
    @ObservationIgnored private var power: PowerEvents?
    @ObservationIgnored private var askedForTrust = false
    @ObservationIgnored private var lastPrune = Date.distantPast
    @ObservationIgnored private var recorder: CallAudioRecorder?

    /// `owner` is the person who uses this Mac, as the Kernel names a person, or why there is none yet. Only the sources
    /// that store lines need it, and they fail closed without it.
    public init(store: Store, owner: Result<PersonID, any Error>) throws {
        self.store = store
        ownerResult = owner
        let policy = try store.currentPolicy()
        self.policy = policy
        status = policy.status(accessibilityGranted: ScreenReader.isTrusted, at: store.clock())
        loop = CaptureLoop(store: store)
        try store.closeInterruptedRecordings()
        try store.closeInterruptedRuns()
    }

    /// The owner of every source this Mac reads. Throws why there is none.
    public func owner() throws -> PersonID { try ownerResult.get() }

    public func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.interval)
            }
        }
        power = PowerEvents { [weak self] event in self?.system(event) }
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        power?.stop()
        power = nil
        setWhatsAppWatch(on: false)
    }

    /// The new policy is saved as one consent event, then used by the next reading.
    public func update(_ change: (inout CapturePolicy) -> Void) throws {
        var changed = policy
        change(&changed)
        guard changed != policy else { return }
        try store.savePolicy(changed)
        policy = changed
        refreshStatus()
    }

    public func keptToday(limit: Int) throws -> [Activity] {
        let today = Calendar.current.startOfDay(for: store.clock())
        let shown = try store.queries.activities(since: today).filter { $0.kind == .window || $0.kind == .file }
        return Array(shown.suffix(limit).reversed())
    }

    /// Recordings that started on or after `start`, newest first.
    public func recordings(since start: Date) throws -> [Recording] {
        try store.queries.recordings().filter { $0.startedAt >= start }
    }

    public func forget(_ activity: Activity) throws {
        guard let id = activity.id else { return }
        try store.delete(.activities(ActivityFilter(id: id)))
    }

    /// Records a call in the app the founder chose, or in person (nil: the microphone only). The policy decides; in
    /// private mode the founder confirms first.
    public func startCall(in app: AudioApp?, confirmed: Bool = false) async throws {
        guard call == nil else { return }
        let now = store.clock()
        let label = app?.bundleID ?? Self.inPerson
        let grant: CaptureGrant
        switch policy.authorize(CaptureRequest(kind: .call, label: label, liveSession: true), at: now) {
        case .allow(let granted): grant = granted
        case .confirm(let pending):
            guard confirmed else { throw CallStartError.needsConfirmation }
            grant = pending.confirmed(at: now)
        case .deny(let reason): throw CallStartError.denied(reason)
        }
        guard await CallAudioRecorder.requestMicrophone() else { throw CallAudioError.microphoneDenied }
        let recording = try store.startRecording(app: app?.name ?? "In person", bundleID: label, grant: grant)
        let recorder = CallAudioRecorder(app: app, folder: recording.folder)
        do {
            try recorder.start()
        } catch {
            try store.finishRecording(recording.id, error: error.localizedDescription)
            throw error
        }
        self.recorder = recorder
        call = recording
    }

    /// The recording is saved only when every track closed with sound in it; otherwise it is kept as failed, with why.
    public func stopCall() throws {
        guard let call, let recorder else { return }
        self.call = nil
        self.recorder = nil
        do {
            try recorder.stop()
        } catch {
            try store.finishRecording(call.id, error: error.localizedDescription)
            throw error
        }
        try store.finishRecording(call.id)
    }

    static let inPerson = "in-person"

    /// Deletes every kind of captured data older than the retention, at most once an hour.
    func pruneIfDue(at now: Date) async {
        guard now.timeIntervalSince(lastPrune) >= 3600 else { return }
        lastPrune = now
        report(await loop.forget(before: now.addingTimeInterval(-CapturePolicy.retention)))
    }

    private func tick() {
        refreshStatus()
        let apps = AudioApps.playing()
        if apps != playingApps { playingApps = apps }
        let now = store.clock()
        Task { await pruneIfDue(at: now) }
        let isCapturing = status == .capturing || status == .needsPermission
        setWhatsAppWatch(
            on: isCapturing && policy.isEnabled(.whatsapp) && policy.allowList[.whatsapp]?.isEmpty == false)
        guard status == .capturing, policy.isEnabled(.screen), let app = FrontApp.current() else {
            requestTrustOnce()
            return
        }
        let (policy, idle) = (policy, Presence.idleSeconds())
        Task { report(await loop.capture(app, idleSeconds: idle, policy: policy, at: now)) }
    }

    private func requestTrustOnce() {
        guard status == .needsPermission, !askedForTrust else { return }
        askedForTrust = true
        ScreenReader.requestTrust()
    }

    private func report(_ failure: String?) {
        if problem != failure { problem = failure }
    }

    private func refreshStatus() {
        status = policy.status(accessibilityGranted: ScreenReader.isTrusted, at: store.clock())
    }

    private func system(_ event: CaptureEngine.SystemEvent) {
        let (policy, now) = (policy, store.clock())
        Task { report(await loop.system(event, policy: policy, at: now)) }
    }

    private func setWhatsAppWatch(on: Bool) {
        if on, whatsAppWatch == nil {
            switch ownerResult {
            case .success(let owner):
                whatsAppWatch = WhatsAppIngestWatch(store: store, owner: owner) { [weak self] failure in
                    self?.report(failure)
                }
            case .failure(let error): report(error.localizedDescription)
            }
        } else if !on, let watch = whatsAppWatch {
            watch.stop()
            whatsAppWatch = nil
        }
    }
}

public enum CallStartError: Error, Equatable {
    case needsConfirmation
    case denied(DenyReason)
}

extension CallStartError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .needsConfirmation: "Private mode is on. Choose “Record a call anyway” to start."
        case .denied(.captureOff): "Capture is off. Turn it on in the menu first."
        case .denied(.paused): "Capture is paused. Choose “Resume” first."
        case .denied(.privateMode): "Private mode is on. Choose “Record a call anyway” to start."
        case .denied(.sourceSwitchedOff): "Turn on “Record calls I start” in Settings > General."
        case .denied(.labelDenied): "This app is on your list of apps Workbench never reads."
        case .denied(.labelNotAllowed): "This app is not on your list of allowed apps."
        }
    }

    public var needsCallSwitch: Bool { self == .denied(.sourceSwitchedOff) }
}

/// The engine, the reader and the store writes, on one actor: the accessibility reads never run on the main thread.
/// Each step returns its failure in plain words, or nil.
actor CaptureLoop {
    private let store: Store
    private let reader = ScreenReader()
    private var engine = CaptureEngine()

    init(store: Store) { self.store = store }

    func capture(_ app: FrontApp, idleSeconds: TimeInterval, policy: CapturePolicy, at now: Date) -> String? {
        var snapshot = reader.read(app, withText: false)
        if idleSeconds < engine.idleAfter, engine.wantsText(for: snapshot, policy: policy, at: now) {
            snapshot = reader.read(app, withText: true)
        }
        return keep(engine.observe(snapshot, idleSeconds: idleSeconds, policy: policy, at: now))
    }

    func system(_ event: CaptureEngine.SystemEvent, policy: CapturePolicy, at now: Date) -> String? {
        keep(engine.system(event, policy: policy, at: now))
    }

    func forget(before cutoff: Date) -> String? {
        failure("delete old data") { try store.delete(.everything(before: cutoff)) }
    }

    private func keep(_ batch: ActivityBatch?) -> String? {
        guard let batch else { return nil }
        return failure("save activity") { try store.record(batch) }
    }

    private func failure(_ step: String, _ body: () throws -> Void) -> String? {
        do {
            try body()
            return nil
        } catch {
            return "Could not \(step): \(error.localizedDescription)"
        }
    }
}

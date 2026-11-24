import AppKit
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
    /// The consent kinds whose lines live in the evidence store under a label the person names.
    static let evidenceKinds = SourceRegistry.all.filter(\.requiresContainerAllowList).map(\.consent)

    public private(set) var policy: CapturePolicy
    public private(set) var status: CaptureStatus
    public private(set) var call: Recording?
    /// Apps playing sound now, refreshed every tick: the calls that can be recorded.
    public private(set) var playingApps: [AudioApp] = []
    public private(set) var listeningApps: [AudioApp] = []
    @ObservationIgnored public var onListening: (([AudioApp]) -> Void)?
    /// The last write or delete that failed in the background, in plain words. Nil after the next one succeeds.
    public private(set) var problem: String?

    @ObservationIgnored private let ownerResult: Result<PersonID, any Error>
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let loop: CaptureLoop
    @ObservationIgnored private let presence = SystemPresence()
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var watchers: [String: any SourceWatching] = [:]
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
        loop = CaptureLoop(store: store, presence: presence, owner: try? owner.get())
        try store.closeInterruptedRecordings()
        try store.closeInterruptedRuns()
        if case .success(let person) = owner {
            try store.moveMailPartsToEvidence(owner: person)
            try store.moveScreenStretchesToEvidence(owner: person)
        }
    }

    /// The owner of every source this Mac reads. Throws why there is none.
    public func owner() throws -> PersonID { try ownerResult.get() }

    /// Keeps the connections of the person's own LinkedIn data export. Their pick of the file is the consent; nothing
    /// on LinkedIn is opened or driven.
    public func importLinkedIn(from file: URL) throws -> LinkedInImportReport {
        try store.importLinkedInConnections(try LinkedInExportFile.connections(in: file), owner: owner())
    }

    /// Whether the sensors are being read now.
    public var isRunning: Bool { ticker != nil }

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

    /// Writes the open stretch before the app quits, and waits for it, so a quit loses no stretch.
    public func endForQuit() {
        let (loop, policy, now) = (loop, policy, store.clock())
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            _ = await loop.stopStretch(policy: policy, at: now)
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    public func stop() {
        ticker?.cancel()
        ticker = nil
        power?.stop()
        power = nil
        updateWatchers(isCapturing: false)
    }

    /// The new policy is saved as one consent event, then used by the next reading. A WhatsApp chat, a Telegram group or a mail label
    /// taken off the allow-list has its lines, and the copies of their words, erased: the consent is withdrawn.
    public func update(_ change: (inout CapturePolicy) -> Void) throws {
        var changed = policy
        change(&changed)
        guard changed != policy else { return }
        let withdrawn = Self.evidenceKinds.map { kind in (kind, policy.withdrawn(kind, in: changed)) }
        try store.savePolicy(changed)
        policy = changed
        refreshStatus()
        for (kind, labels) in withdrawn {
            for label in labels { try store.eraseEvidence(.grant(kind: kind, label: label)) }
        }
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

    /// Deletes everything kept of one kind of source, with the copies of its words.
    public func forgetAll(_ kind: SourceKind) throws {
        try store.delete(.kind(kind, before: nil))
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
        let recording = try store.startRecording(
            app: app?.name ?? "In person", bundleID: label, source: source(of: app), grant: grant)
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

    /// The service and meeting of a call in `app`. The call window's title and address are screen content, so they
    /// are read only under the app's own screen consent; without it the call is named by its app.
    public func source(of app: AudioApp?) -> CallSource {
        guard let app else {
            return CallSource.identify(app: "", bundleID: Self.inPerson, windowTitle: "", address: "")
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first
        let screen = policy.authorize(CaptureRequest(kind: .screen, label: app.bundleID), at: store.clock()).grant
        guard ScreenReader.isTrusted, let running, let screen else {
            return CallSource.identify(app: app.name, bundleID: app.bundleID, windowTitle: "", address: "")
        }
        let front = FrontApp(
            pid: running.processIdentifier, name: app.name, bundleID: app.bundleID,
            isBrowser: running.bundleURL.map(WebBrowserApp.isBrowser) ?? false)
        let window = ScreenReader().read(front, grant: screen, withText: false)
        return CallSource.identify(
            app: app.name, bundleID: app.bundleID, windowTitle: window.title, address: window.document)
    }

    /// The hourly hook: deletes every kind of captured data older than the retention, then keeps the store safe (the
    /// check after launch and the daily snapshot). The first problem found is shown.
    func pruneIfDue(at now: Date) async {
        guard now.timeIntervalSince(lastPrune) >= 3600 else { return }
        lastPrune = now
        let pruned = await loop.forget(before: now.addingTimeInterval(-CapturePolicy.retention))
        let kept = await loop.keepStoreSafe()
        report(pruned ?? kept)
    }

    private func tick() {
        refreshStatus()
        let apps = AudioApps.playing()
        if apps != playingApps { playingApps = apps }
        let listening = AudioApps.listening()
        if listening != listeningApps { listeningApps = listening }
        onListening?(listening)
        let now = store.clock()
        Task { await pruneIfDue(at: now) }
        let isCapturing = status == .capturing || status == .needsPermission
        updateWatchers(isCapturing: isCapturing)
        let policy = policy
        guard status == .capturing, policy.isEnabled(.screen) else {
            Task { report(await loop.stopStretch(policy: policy, at: now)) }
            requestTrustOnce()
            return
        }
        guard let app = FrontApp.current() else { return }
        Task { report(await loop.capture(app, policy: policy, at: now)) }
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
        presence.note(event)
        let (policy, now) = (policy, store.clock())
        Task { report(await loop.system(event, policy: policy, at: now)) }
    }

    private func updateWatchers(isCapturing: Bool) {
        for watcher in SourceWatcher.all {
            let key = watcher.descriptor.key
            if isCapturing && isWatchable(watcher.descriptor) {
                guard watchers[key] == nil else { continue }
                switch ownerResult {
                case .success(let owner):
                    watchers[key] = watcher.start(store, owner) { [weak self] failure in self?.report(failure) }
                case .failure(let error): report(error.localizedDescription)
                }
            } else {
                watchers.removeValue(forKey: key)?.stop()
            }
        }
    }

    /// A source is watched while its switch is on and, when it reads only named containers, the person named one.
    private func isWatchable(_ descriptor: SourceDescriptor) -> Bool {
        policy.isEnabled(descriptor.consent)
            && (!descriptor.requiresContainerAllowList || policy.allowList[descriptor.consent]?.isEmpty == false)
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
    private let reader: any ScreenReading
    private let presence: any PresenceSource
    private let owner: PersonID?
    private var engine = CaptureEngine()
    private var screen = ScreenKeeper()
    private var storeIsChecked = false

    /// `owner` is the person who uses this Mac. Without one the screen lines are not kept: the rows of the capture log
    /// still are.
    init(
        store: Store, presence: any PresenceSource, owner: PersonID? = nil,
        reader: sending any ScreenReading = ScreenReader()
    ) {
        self.store = store
        self.presence = presence
        self.owner = owner
        self.reader = reader
    }

    /// Presence and the bundle-id gate come before any Accessibility call. An app that is not read, or a person who
    /// is not here, gives the engine only what NSWorkspace says, and the engine writes the bare markers.
    func capture(_ app: FrontApp, policy: CapturePolicy, at now: Date) -> String? {
        let state = presence.state(idleAfter: engine.idleAfter)
        let snapshot = snapshot(of: app, presence: state, policy: policy, at: now)
        return keep(engine.observe(snapshot, presence: state, policy: policy, at: now), policy: policy, at: now)
    }

    private func snapshot(of app: FrontApp, presence: PresenceState, policy: CapturePolicy, at now: Date)
        -> ScreenSnapshot
    {
        guard presence == .active, case .read(let grant) = policy.admission(ofApp: app.bundleID, at: now) else {
            return app.unread
        }
        let cheap = reader.read(app, grant: grant, withText: false)
        guard engine.wantsText(for: cheap, policy: policy, at: now) else { return cheap }
        return reader.read(app, grant: grant, withText: true)
    }

    func system(_ event: CaptureEngine.SystemEvent, policy: CapturePolicy, at now: Date) -> String? {
        keep(engine.system(event, policy: policy, at: now), policy: policy, at: now)
    }

    func forget(before cutoff: Date) -> String? {
        failure("delete old data") { try store.delete(.everything(before: cutoff)) }
    }

    /// Checks the store once after launch, then makes the daily snapshot when it is due. A store that fails its check
    /// is checked again each hour and gets no snapshot, so a damaged file never replaces a good backup.
    func keepStoreSafe() -> String? {
        failure("keep your data safe") {
            if !storeIsChecked {
                try store.checkIntegrity()
                storeIsChecked = true
            }
            try store.snapshotIfDue()
        }
    }

    /// Ends the open stretch now, as when capture pauses or stops or the app quits. It is kept only if the app's consent
    /// still holds.
    func stopStretch(policy: CapturePolicy, at now: Date) -> String? {
        failure("save activity") { try write(screen.writes(stoppingAt: now, policy: policy)) }
    }

    /// Keeps the batch in the capture log and, with an owner, the screen lines it gives. No batch is a quiet tick.
    private func keep(_ batch: ActivityBatch?, policy: CapturePolicy, at now: Date) -> String? {
        failure("save activity") {
            guard let batch else { return try write(screen.writes(idleAt: now, policy: policy)) }
            let ids = try store.record(batch)
            try write(screen.writes(for: batch, ids: ids, policy: policy, at: now))
        }
    }

    private func write(_ writes: [ScreenWrite]) throws {
        guard let owner else { return }
        for write in writes { _ = try store.record(write.reading, of: write.descriptor, owner: owner) }
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

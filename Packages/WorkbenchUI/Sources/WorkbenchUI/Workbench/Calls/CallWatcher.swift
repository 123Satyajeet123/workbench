import CaptureService
import Foundation
import LocalSources
import Observation
import WorkbenchCore

protocol CallControls: AnyObject {
    var recordingApp: String? { get }
    var callsAllowed: Bool { get }
    var isPrivate: Bool { get }
    func record(_ app: AudioApp, confirmed: Bool)
    func stopRecording()
}

extension CaptureSettings: CallControls {
    var recordingApp: String? { call?.bundleID }
    var callsAllowed: Bool { isOn(.call) && (mode == .on || mode == .privateHour) }
    var isPrivate: Bool { mode == .privateHour }
    func record(_ app: AudioApp, confirmed: Bool) { startCall(in: app, confirmed: confirmed) }
    func stopRecording() { stopCall() }
}

@MainActor @Observable
final class CallWatcher {
    struct Offer: Equatable {
        var app: AudioApp
        var source: CallSource
    }

    private static let alwaysKey = StateKey<[String: String]>.json("calls.always")

    private(set) var offer: Offer?
    private(set) var always: [String: String]
    let problems = ProblemSlot()

    @ObservationIgnored private var detector = CallDetector()
    @ObservationIgnored private var followed: String?
    @ObservationIgnored private let store: Store
    @ObservationIgnored private let controls: any CallControls
    @ObservationIgnored private let announce: (String, String) -> Void
    @ObservationIgnored private let identify: (AudioApp) -> CallSource

    init(
        store: Store, controls: any CallControls, announce: @escaping (String, String) -> Void,
        identify: @escaping (AudioApp) -> CallSource
    ) {
        self.store = store
        self.controls = controls
        self.announce = announce
        self.identify = identify
        always = ((try? Self.alwaysKey.load(from: store)) ?? nil) ?? [:]
    }

    func update(listening: [AudioApp], at now: Date) {
        guard controls.callsAllowed else {
            offer = nil
            followed = nil
            detector = CallDetector()
            return
        }
        let apps = Dictionary(listening.map { ($0.bundleID, $0) }, uniquingKeysWith: { first, _ in first })
        for event in detector.update(listening: Set(apps.keys), at: now) {
            switch event {
            case .started(let id): if let app = apps[id] { started(app) }
            case .ended(let id): ended(id)
            }
        }
    }

    func record() {
        guard let offer else { return }
        self.offer = nil
        follow(offer.app, confirmed: controls.isPrivate)
    }

    func recordAlways() {
        guard let offer else { return }
        always[offer.app.bundleID] = offer.app.name
        saveAlways()
        record()
    }

    func dismiss() { offer = nil }

    func forget(_ bundleID: String) {
        always[bundleID] = nil
        saveAlways()
    }

    private func started(_ app: AudioApp) {
        guard controls.recordingApp == nil else { return }
        let source = identify(app)
        if always[app.bundleID] != nil, !controls.isPrivate {
            follow(app, confirmed: false)
            announce(
                "Recording your \(source.label) call",
                "It stops when the call ends. Stop it sooner from the notch or the menu bar.")
        } else {
            offer = Offer(app: app, source: source)
            announce("Record this \(source.label) call?", "Choose Record in the notch, or open Echo.")
        }
    }

    private func ended(_ id: String) {
        if offer?.app.bundleID == id { offer = nil }
        guard followed == id else { return }
        followed = nil
        if controls.recordingApp == id { controls.stopRecording() }
    }

    private func follow(_ app: AudioApp, confirmed: Bool) {
        followed = app.bundleID
        controls.record(app, confirmed: confirmed)
    }

    private func saveAlways() {
        problems.attempt("save the apps to record", clearing: true) { try Self.alwaysKey.save(always, to: store) }
    }
}

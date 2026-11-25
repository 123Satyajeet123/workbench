import AVFoundation
import AppKit
import CoreAudio
import Synchronization

public enum CallAudioError: Error, Equatable {
    case coreAudio(String, OSStatus)
    case noProcesses(String)
    case microphoneDenied
    /// No track kept any sound. The text says what was lost, in plain words.
    case nothingSaved(String)
    /// Without this Info.plist key macOS refuses the system-audio permission and the tap records only silence.
    case missingAudioCaptureUsage
}

/// An app that is playing sound, with every audio process it owns: a browser call plays through helper processes.
public struct AudioApp: Sendable, Hashable, Identifiable {
    public var bundleID: String
    public var name: String
    public var processes: [AudioObjectID]

    public var id: String { bundleID }

    public init(bundleID: String, name: String, processes: [AudioObjectID]) {
        self.bundleID = bundleID
        self.name = name
        self.processes = processes
    }
}

public struct AudioProcess: Sendable, Equatable {
    public var id: AudioObjectID
    public var bundleID: String
    public var isPlaying: Bool
    public var isListening = false
}

public enum AudioApps {
    /// Apps with at least one process producing sound now, Workbench excluded.
    @MainActor
    public static func playing() -> [AudioApp] { group(ownedProcesses(), apps: regularApps()) }

    @MainActor
    public static func listening() -> [AudioApp] {
        group(ownedProcesses(), apps: regularApps(), where: \.isListening)
    }

    @MainActor
    private static func regularApps() -> [String: String] {
        Dictionary(
            NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { app in
                app.bundleIdentifier.map { ($0, app.localizedName ?? $0) }
            }, uniquingKeysWith: { first, _ in first })
    }

    private static func ownedProcesses() -> [AudioProcess] {
        let own = Bundle.main.bundleIdentifier ?? ""
        return processes().filter { !$0.bundleID.hasPrefix(own) || own.isEmpty }
    }

    /// Each process belongs to the running app whose bundle ID is its own or a dotted prefix of it.
    public static func group(
        _ processes: [AudioProcess], apps: [String: String], where active: (AudioProcess) -> Bool = \.isPlaying
    ) -> [AudioApp] {
        var owned: [String: [AudioProcess]] = [:]
        for process in processes {
            let owners = apps.keys.filter { process.bundleID == $0 || process.bundleID.hasPrefix($0 + ".") }
            guard let owner = owners.max(by: { $0.count < $1.count }) else { continue }
            owned[owner, default: []].append(process)
        }
        return owned.filter { $0.value.contains(where: active) }
            .map { AudioApp(bundleID: $0.key, name: apps[$0.key] ?? $0.key, processes: $0.value.map(\.id).sorted()) }
            .sorted { $0.name < $1.name }
    }

    static func processes() -> [AudioProcess] {
        let ids: [AudioObjectID] = CoreAudioProperty.array(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList)
        return ids.compactMap { id in
            guard let bundleID: CFString = CoreAudioProperty.value(id, kAudioProcessPropertyBundleID) else {
                return nil
            }
            let playing: UInt32 = CoreAudioProperty.value(id, kAudioProcessPropertyIsRunningOutput) ?? 0
            let listening: UInt32 = CoreAudioProperty.value(id, kAudioProcessPropertyIsRunningInput) ?? 0
            return AudioProcess(
                id: id, bundleID: bundleID as String, isPlaying: playing != 0, isListening: listening != 0)
        }
    }
}

/// What a stopped call kept: the files of each track and the sound each track lost.
public struct CallAudioResult: Sendable, Equatable {
    var tracks: [TrackOutcome]

    public var files: [URL] { tracks.flatMap(\.files) }

    /// What is missing, in plain words, with what was kept. Nil when every track is whole.
    public var lossNote: String? {
        let (whole, damaged) = (tracks.filter(\.isWhole), tracks.filter { !$0.isWhole })
        guard !damaged.isEmpty else { return nil }
        return (damaged.map(\.sentence) + whole.map { "\($0.person.capitalizedFirst) was saved in full." })
            .joined(separator: " ")
    }
}

extension TrackOutcome {
    fileprivate var isWhole: Bool { !files.isEmpty && lost == 0 }

    fileprivate var person: String { track == "me" ? "your voice" : "the other side" }

    fileprivate var sentence: String {
        if files.isEmpty && lost == 0 { return "\(person.capitalizedFirst) got no sound, so nothing of it was saved." }
        if files.isEmpty { return "\(person.capitalizedFirst) was not saved." }
        return "\(person.capitalizedFirst) was saved, but \(Self.spoken(lost)) of it is missing."
    }

    fileprivate static func spoken(_ seconds: TimeInterval) -> String {
        let whole = max(1, Int(seconds.rounded(.up)))
        return whole < 60 ? "\(whole) s" : "\(whole / 60) min \(whole % 60) s"
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

public enum CallTracks {
    public static func files(in folder: URL) -> (me: [URL], them: [URL]) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let track = { (prefix: String) in
            names.filter { $0.hasPrefix(prefix + "-") && $0.hasSuffix(".m4a") }.sorted()
                .map { folder.appending(path: $0) }
        }
        return (track("me"), track("them"))
    }

    public static func duration(of file: URL) -> TimeInterval {
        guard let audio = try? AVAudioFile(forReading: file), audio.processingFormat.sampleRate > 0 else { return 0 }
        return Double(audio.length) / audio.processingFormat.sampleRate
    }
}

/// Records one call: the `me` track from the microphone and, for an online call, the `them` track from a process tap
/// on the call app. In person (no app) the microphone hears everyone. Nothing starts on its own; the owner calls
/// `start` and `stop`.
@MainActor
public final class CallAudioRecorder {
    public let folder: URL

    private let app: AudioApp?
    private var tap: ProcessTap?
    private var microphone: AudioFileSink?
    private var microphoneOffSince: Date?
    private var configurationObserver: (any NSObjectProtocol)?
    private let engine = AVAudioEngine()

    public init(app: AudioApp?, folder: URL) {
        self.app = app
        self.folder = folder
    }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public static var microphoneRefused: Bool {
        [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let app {
            guard Bundle.main.object(forInfoDictionaryKey: "NSAudioCaptureUsageDescription") != nil else {
                throw CallAudioError.missingAudioCaptureUsage
            }
            guard !app.processes.isEmpty else { throw CallAudioError.noProcesses(app.bundleID) }
            tap = try ProcessTap(processes: app.processes, folder: folder)
        }
        do {
            try startMicrophone()
        } catch {
            stop()
            throw error
        }
    }

    /// Stops both tracks and closes their files. The result tells what each track kept and what it lost.
    @discardableResult
    public func stop() -> CallAudioResult {
        let them = tap?.stop()
        tap = nil
        configurationObserver.map(NotificationCenter.default.removeObserver)
        configurationObserver = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        if let microphoneOffSince { microphone?.noteLost(Date().timeIntervalSince(microphoneOffSince)) }
        microphoneOffSince = nil
        let me = microphone?.finish()
        microphone = nil
        return CallAudioResult(tracks: [me, them].compactMap(\.self))
    }

    private func startMicrophone() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw CallAudioError.microphoneDenied
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let sink = AudioFileSink(folder: folder, track: "me", format: format)
        microphone = sink
        Self.installTap(on: input, format: format, sink: sink)
        try engine.start()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.restartMicrophone() } }
    }

    /// The engine stops itself when the input device changes its rate or channel count. This starts it again on the
    /// new format; the sink converts each buffer. The time the microphone was off is counted as lost.
    private func restartMicrophone() {
        guard let microphone else { return }
        let offSince = microphoneOffSince ?? Date()
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        do {
            guard format.sampleRate > 0, format.channelCount > 0 else { throw CallAudioError.coreAudio("input", -1) }
            Self.installTap(on: input, format: format, sink: microphone)
            try engine.start()
            microphone.noteLost(Date().timeIntervalSince(offSince))
            microphoneOffSince = nil
        } catch {
            microphoneOffSince = offSince
        }
    }

    /// The tap block runs on an audio thread, so it must not be made in a main-actor context.
    private nonisolated static func installTap(on input: AVAudioInputNode, format: AVAudioFormat, sink: AudioFileSink) {
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in sink.write(buffer) }
    }
}

/// A private, unmuted tap on given processes, read through a private aggregate device.
final class ProcessTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sink: AudioFileSink?
    private let queue = DispatchQueue(label: "workbench.call.tap")

    init(processes: [AudioObjectID], folder: URL) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.muteBehavior = .unmuted
        description.isPrivate = true
        try check("create tap", AudioHardwareCreateProcessTap(description, &tapID))
        do {
            try makeDevice(tapUID: description.uuid.uuidString)
            var stream: AudioStreamBasicDescription = try CoreAudioProperty.required(tapID, kAudioTapPropertyFormat)
            guard let format = AVAudioFormat(streamDescription: &stream) else {
                throw CallAudioError.coreAudio("tap format", -1)
            }
            let sink = AudioFileSink(folder: folder, track: "them", format: format)
            self.sink = sink
            try check(
                "io proc",
                AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { _, input, _, _, _ in
                    sink.write(input, format: format)
                })
            try check("start", AudioDeviceStart(deviceID, procID))
        } catch {
            stop()
            throw error
        }
    }

    @discardableResult
    func stop() -> TrackOutcome? {
        stopDevice()
        defer { sink = nil }
        return sink?.finish()
    }

    private func stopDevice() {
        if let procID {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
            self.procID = nil
        }
        if deviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(deviceID)
            deviceID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func makeDevice(tapUID: String) throws {
        let output: AudioObjectID = try CoreAudioProperty.required(
            AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultSystemOutputDevice)
        let outputUID: CFString = try CoreAudioProperty.required(output, kAudioDevicePropertyDeviceUID)
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Workbench call",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: tapUID]],
        ]
        try check("aggregate device", AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID))
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw CallAudioError.coreAudio(step, status) }
    }
}

enum CoreAudioProperty {
    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }

    static func required<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> T {
        guard let value: T = value(object, selector) else { throw CallAudioError.coreAudio("property \(selector)", -1) }
        return value
    }

    static func array(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}

extension CallAudioError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .coreAudio(let step, let status): "macOS refused the audio request (\(step), code \(status))."
        case .noProcesses(let app): "\(app) is not playing sound, so there is nothing to record."
        case .microphoneDenied: "macOS refused microphone access. Allow it in System Settings > Privacy & Security."
        case .missingAudioCaptureUsage: "This build cannot ask macOS for call audio, so call recording cannot start."
        case .nothingSaved(let note): note
        }
    }
}

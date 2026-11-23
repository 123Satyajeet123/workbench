import AVFoundation
import AppKit
import CoreAudio
import Synchronization

public enum CallAudioError: Error, Equatable {
    case coreAudio(String, OSStatus)
    case noProcesses(String)
    case microphoneDenied
    case write(track: String, reason: String)
    case emptyTrack(String)
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
            _ = try? stop()
            throw error
        }
    }

    /// Stops both tracks and closes their files. Throws the first write error, or when a track kept no sound frame.
    @discardableResult
    public func stop() throws -> [URL] {
        let them = try tap?.stop()
        tap = nil
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        let me = try microphone?.finish()
        microphone = nil
        return (me ?? []) + (them ?? [])
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
            _ = try? stop()
            throw error
        }
    }

    func stop() throws -> [URL] {
        stopDevice()
        defer { sink = nil }
        return try sink?.finish() ?? []
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

/// One track as AAC files of at most `segment` each: a crash loses only the open file. The first write error stops
/// the track and is kept for `finish`.
final class AudioFileSink: @unchecked Sendable {
    private struct State {
        var file: AVAudioFile?
        var frames: AVAudioFramePosition = 0
        var files: [URL] = []
        var failure: CallAudioError?
        var finished = false
    }

    private let folder: URL
    private let track: String
    private let format: AVAudioFormat
    private let segment: TimeInterval
    private let state = Mutex(State())

    init(folder: URL, track: String, format: AVAudioFormat, segment: TimeInterval = 300) {
        self.folder = folder
        self.track = track
        self.format = format
        self.segment = segment
    }

    func write(_ buffer: AVAudioPCMBuffer) {
        state.withLock { state in
            guard !state.finished, state.failure == nil else { return }
            do {
                if state.file == nil || Double(state.frames) >= segment * format.sampleRate {
                    state.file?.close()
                    let url = folder.appending(path: String(format: "%@-%03d.m4a", track, state.files.count + 1))
                    state.file = try AVAudioFile(
                        forWriting: url, settings: settings, commonFormat: format.commonFormat,
                        interleaved: format.isInterleaved)
                    state.files.append(url)
                    state.frames = 0
                }
                try state.file?.write(from: buffer)
                state.frames += AVAudioFramePosition(buffer.frameLength)
            } catch {
                state.failure = .write(track: track, reason: error.localizedDescription)
                state.file?.close()
                state.file = nil
            }
        }
    }

    func write(_ list: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list) else { return }
        write(buffer)
    }

    /// Closes the open file. Returns every file of the track, or the first failure.
    func finish() throws -> [URL] {
        let (files, failure) = state.withLock { state in
            state.finished = true
            state.file?.close()
            state.file = nil
            return (state.files, state.failure)
        }
        if let failure { throw failure }
        guard !files.isEmpty else { throw CallAudioError.emptyTrack(track) }
        return files
    }

    private var settings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: min(format.channelCount, 2), AVEncoderBitRateKey: 64_000,
        ]
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
        case .write(let track, let reason): "Workbench could not save the \(track) track: \(reason)"
        case .emptyTrack(let track): "The \(track) track got no sound, so nothing was saved."
        }
    }
}

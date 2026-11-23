import AVFoundation
import Foundation
import LocalSources
import Observation
import WorkbenchCore

@MainActor @Observable
final class CallPlayback {
    private(set) var recordingID: Int64?
    private(set) var isPlaying = false
    private(set) var time: Double = 0
    private(set) var duration: Double = 0
    private(set) var problem: String?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var ticks: Any?
    @ObservationIgnored private var ending: NSObjectProtocol?

    init() {
        ticks = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] now in
            MainActor.assumeIsolated { self?.tick(now.seconds) }
        }
        ending = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let item = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.finished(item) }
        }
    }

    func isCurrent(_ recording: Recording) -> Bool { recordingID == recording.id }

    func toggle(_ recording: Recording) async {
        if isCurrent(recording) {
            isPlaying ? pause() : play()
        } else if await load(recording) {
            play()
        }
    }

    func seek(_ recording: Recording, to seconds: Double, andPlay: Bool = false) async {
        if !isCurrent(recording) {
            guard await load(recording) else { return }
        }
        time = min(max(seconds, 0), duration)
        await player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if andPlay { play() }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    private func play() {
        guard player.currentItem != nil else { return }
        if duration > 0, time >= duration - 0.05 {
            time = 0
            player.seek(to: .zero)
        }
        player.play()
        isPlaying = true
    }

    private func load(_ recording: Recording) async -> Bool {
        pause()
        let tracks = CallTracks.files(in: recording.folder)
        do {
            let composition = try await Self.composition(me: tracks.me, them: tracks.them)
            player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
            recordingID = recording.id
            duration = try await composition.load(.duration).seconds
            time = 0
            problem = nil
            return true
        } catch {
            player.replaceCurrentItem(with: nil)
            recordingID = recording.id
            duration = 0
            time = 0
            problem = "This call can't be played: \(error.localizedDescription)"
            return false
        }
    }

    private func tick(_ seconds: Double) {
        guard isPlaying, seconds.isFinite else { return }
        time = min(seconds, duration)
    }

    private func finished(_ item: ObjectIdentifier?) {
        guard let item, item == player.currentItem.map(ObjectIdentifier.init) else { return }
        isPlaying = false
        time = duration
    }

    nonisolated static func composition(me: [URL], them: [URL]) async throws -> AVComposition {
        let composition = AVMutableComposition()
        for files in [me, them] where !files.isEmpty {
            guard
                let track = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            var cursor = CMTime.zero
            for file in files {
                let asset = AVURLAsset(url: file)
                guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let length = try await asset.load(.duration)
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: cursor)
                cursor = cursor + length
            }
        }
        guard !composition.tracks.isEmpty else { throw CocoaError(.fileNoSuchFile) }
        return composition
    }
}

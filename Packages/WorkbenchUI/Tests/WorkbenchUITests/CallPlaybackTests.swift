import AVFoundation
import Foundation
import Testing
import WorkbenchCore

@testable import WorkbenchUI

@MainActor struct CallPlaybackTests {
    private func silence(_ seconds: Double, at url: URL) throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let file = try AVAudioFile(
            forWriting: url,
            settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1])
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(16_000 * seconds)))
        buffer.frameLength = buffer.frameCapacity
        try file.write(from: buffer)
    }

    private func call(in store: Store, files: [String: Double]) throws -> Recording {
        let grant = try #require(
            CapturePolicy(switches: [.call: true])
                .authorize(CaptureRequest(kind: .call, label: "us.zoom.xos", liveSession: true), at: Date()).grant)
        let recording = try store.startRecording(app: "zoom.us", bundleID: "us.zoom.xos", grant: grant)
        for (name, seconds) in files { try silence(seconds, at: recording.folder.appending(path: name)) }
        try store.finishRecording(recording.id)
        return recording
    }

    @Test func bothSidesPlayAsOneTimelineAcrossTheirFiles() async throws {
        let store = try scratchStore()
        let recording = try call(in: store, files: ["me-001.m4a": 2, "me-002.m4a": 2, "them-001.m4a": 3])
        let composition = try await CallPlayback.composition(
            me: [recording.folder.appending(path: "me-001.m4a"), recording.folder.appending(path: "me-002.m4a")],
            them: [recording.folder.appending(path: "them-001.m4a")])
        #expect(composition.tracks.count == 2)
        #expect(abs(try await composition.load(.duration).seconds - 4) < 0.2)
    }

    @Test func playPauseAndSeekFollowTheCallThatIsOpen() async throws {
        let store = try scratchStore()
        let one = try call(in: store, files: ["me-001.m4a": 4, "them-001.m4a": 4])
        let two = try call(in: store, files: ["them-001.m4a": 2])
        let playback = CallPlayback()

        await playback.toggle(one)
        #expect(playback.isCurrent(one) && playback.isPlaying && abs(playback.duration - 4) < 0.2)
        await playback.seek(one, to: 3)
        #expect(playback.time == 3)
        await playback.toggle(one)
        #expect(!playback.isPlaying)

        await playback.seek(two, to: 9)
        #expect(playback.isCurrent(two) && !playback.isPlaying && playback.time == playback.duration)
        playback.pause()
    }

    @Test func aCallWithoutAudioSaysItCannotBePlayed() async throws {
        let store = try scratchStore()
        let empty = try call(in: store, files: [:])
        let playback = CallPlayback()
        await playback.toggle(empty)
        #expect(playback.isCurrent(empty) && !playback.isPlaying && playback.problem != nil)
        await playback.toggle(empty)
        #expect(!playback.isPlaying)
    }
}

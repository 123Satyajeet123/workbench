import AVFoundation
import Testing

@testable import LocalSources

struct AudioAppsTests {
    private let apps = [
        "com.brave.Browser": "Brave Browser", "net.whatsapp.WhatsApp": "WhatsApp", "com.spotify.client": "Spotify",
    ]

    @Test func helpersBelongToTheirAppAndAQuietAppIsNotOffered() {
        let processes = [
            AudioProcess(id: 10, bundleID: "com.brave.Browser", isPlaying: false),
            AudioProcess(id: 11, bundleID: "com.brave.Browser.helper.Renderer", isPlaying: true),
            AudioProcess(id: 20, bundleID: "net.whatsapp.WhatsApp", isPlaying: false),
            AudioProcess(id: 30, bundleID: "com.apple.CoreSpeech", isPlaying: true),
        ]
        let playing = AudioApps.group(processes, apps: apps)
        #expect(playing.map(\.bundleID) == ["com.brave.Browser"])
        #expect(playing.first?.processes == [10, 11])
    }

    @Test func theLongestMatchingAppOwnsAProcessAndAPrefixWithoutADotDoesNot() {
        let nested = apps.merging(["com.brave.Browser.beta": "Brave Beta"]) { first, _ in first }
        let processes = [
            AudioProcess(id: 1, bundleID: "com.brave.Browser.beta.helper", isPlaying: true),
            AudioProcess(id: 2, bundleID: "com.brave.BrowserX", isPlaying: true),
        ]
        #expect(AudioApps.group(processes, apps: nested).map(\.bundleID) == ["com.brave.Browser.beta"])
    }
}

struct AudioFileSinkTests {
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "sink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func tone(seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * format.sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) { buffer.floatChannelData![0][index] = sin(Float(index) * 0.3) * 0.5 }
        return buffer
    }

    @Test func aLongTrackIsSplitIntoClosedReadableSegments() throws {
        let sink = AudioFileSink(folder: try folder(), track: "me", format: format, segment: 1)
        for _ in 0..<3 { sink.write(tone(seconds: 0.6)) }
        let files = try sink.finish()
        #expect(files.map(\.lastPathComponent) == ["me-001.m4a", "me-002.m4a"])
        for file in files { #expect(try AVAudioFile(forReading: file).length > 0) }
        sink.write(tone(seconds: 0.6))
        #expect(try sink.finish() == files)
    }

    @Test func aTrackWithNoSoundFailsAndAWriteErrorFailsTheTrack() throws {
        #expect(throws: CallAudioError.emptyTrack("me")) {
            try AudioFileSink(folder: try folder(), track: "me", format: format).finish()
        }
        let missing = FileManager.default.temporaryDirectory.appending(path: "absent-\(UUID().uuidString)")
        let broken = AudioFileSink(folder: missing, track: "them", format: format)
        broken.write(tone(seconds: 0.1))
        #expect(throws: CallAudioError.self) { try broken.finish() }
    }
}

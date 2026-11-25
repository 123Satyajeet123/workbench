import AVFoundation
import Testing

@testable import LocalSources

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
        let files = sink.finish().files
        #expect(files.map(\.lastPathComponent) == ["me-001.m4a", "me-002.m4a"])
        for file in files { #expect(try AVAudioFile(forReading: file).length > 0) }
        sink.write(tone(seconds: 0.6))
        #expect(sink.finish().files == files)
    }

    @Test func aTrackWithNoSoundKeepsNoFileAndAWriteErrorIsCountedAsLoss() throws {
        let silent = AudioFileSink(folder: try folder(), track: "me", format: format).finish()
        #expect(silent.files.isEmpty && silent.lost == 0)
        let missing = FileManager.default.temporaryDirectory.appending(path: "absent-\(UUID().uuidString)")
        let broken = AudioFileSink(folder: missing, track: "them", format: format)
        broken.write(tone(seconds: 0.1))
        let outcome = broken.finish()
        #expect(outcome.files.isEmpty && outcome.lost > 0)
    }
}

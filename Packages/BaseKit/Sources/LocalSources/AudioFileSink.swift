import AVFoundation
import Synchronization
import os

/// What one track kept: its files, and how much sound it could not write.
struct TrackOutcome: Sendable, Equatable {
    var track: String
    var files: [URL]
    var lost: TimeInterval
}

/// Turns buffers of any format into one fixed format. A call app can change the microphone's rate or channel count
/// in the middle of a call, and `AVAudioFile.write(from:)` needs a buffer in the file's processing format.
struct BufferConverter {
    private var converter: AVAudioConverter?

    mutating func callAsFunction(_ buffer: AVAudioPCMBuffer, to target: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard buffer.format != target else { return buffer }
        if converter?.inputFormat != buffer.format || converter?.outputFormat != target {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter else { throw CallAudioError.coreAudio("convert", kAudioConverterErr_FormatNotSupported) }
        let frames = (Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate).rounded(.up)
        let capacity = AVAudioFrameCount(frames) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw CallAudioError.coreAudio("convert buffer", kAudioConverterErr_UnspecifiedError)
        }
        var offset: AVAudioFrameCount = 0
        var failure: NSError?
        converter.convert(to: output, error: &failure) { requested, status in
            let count = min(requested, buffer.frameLength - offset)
            guard count > 0, let part = buffer.copy(from: offset, count: count) else {
                status.pointee = .noDataNow
                return nil
            }
            offset += count
            status.pointee = .haveData
            return part
        }
        if let failure { throw failure }
        return output
    }
}

extension AVAudioPCMBuffer {
    /// A copy of `count` frames from `start`. The converter asks for input in small steps and drops the rest of a
    /// larger buffer, so it must be fed in pieces.
    fileprivate func copy(from start: AVAudioFrameCount, count: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard let part = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return nil }
        part.frameLength = count
        let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
        let source = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(part.mutableAudioBufferList)
        for (from, to) in zip(source, target) {
            memcpy(to.mData, from.mData! + Int(start) * bytesPerFrame, Int(count) * bytesPerFrame)
        }
        return part
    }
}

/// One track as AAC files of at most `segment` each: a crash loses only the open file. Sound that cannot be written
/// is counted, never allowed to stop the track: the audio already written stays readable and the next buffer is tried.
final class AudioFileSink: @unchecked Sendable {
    private struct State {
        var file: AVAudioFile?
        var converter = BufferConverter()
        var frames: AVAudioFramePosition = 0
        var files: [URL] = []
        var lost: TimeInterval = 0
        var finished = false
    }

    private static let log = Logger(subsystem: "Workbench", category: "call-audio")

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
        guard buffer.frameLength > 0 else { return }
        state.withLock { state in
            guard !state.finished else { return }
            do {
                let file = try openFile(&state)
                let converted = try state.converter(buffer, to: file.processingFormat)
                try file.write(from: converted)
                state.frames += AVAudioFramePosition(converted.frameLength)
            } catch {
                Self.log.error("\(self.track, privacy: .public) track write failed: \(error)")
                state.lost += Double(buffer.frameLength) / buffer.format.sampleRate
                state.file?.close()
                state.file = nil
            }
        }
    }

    func write(_ list: UnsafePointer<AudioBufferList>, format: AVAudioFormat) {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list) else {
            noteLost(Self.duration(of: list.pointee.mBuffers.mDataByteSize, in: format))
            return
        }
        write(buffer)
    }

    private static func duration(of bytes: UInt32, in format: AVAudioFormat) -> TimeInterval {
        Double(bytes) / Double(format.streamDescription.pointee.mBytesPerFrame) / format.sampleRate
    }

    /// Adds sound that never reached `write`, for example the time the microphone was off.
    func noteLost(_ seconds: TimeInterval) {
        state.withLock { $0.lost += seconds }
    }

    /// Closes the open file. It tells what the track kept and what it lost.
    func finish() -> TrackOutcome {
        state.withLock { state in
            state.finished = true
            state.file?.close()
            state.file = nil
            return TrackOutcome(track: track, files: state.files, lost: state.lost)
        }
    }

    private func openFile(_ state: inout State) throws -> AVAudioFile {
        if let file = state.file, Double(state.frames) < segment * format.sampleRate { return file }
        state.file?.close()
        let url = folder.appending(path: String(format: "%@-%03d.m4a", track, state.files.count + 1))
        let file = try AVAudioFile(
            forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        state.file = file
        state.files.append(url)
        state.frames = 0
        return file
    }

    private var settings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: min(format.channelCount, 2), AVEncoderBitRateKey: 64_000,
        ]
    }
}

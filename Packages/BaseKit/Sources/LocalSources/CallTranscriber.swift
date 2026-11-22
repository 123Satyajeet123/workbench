import AVFoundation
import Foundation
import Speech

public protocol CallTranscriber: Sendable {
    var name: String { get }
    func transcribe(_ audio: URL) async throws -> String
}

public enum TranscriberError: Error, Equatable {
    case unsupported(String)
    case notInstalled(String)
}

@available(macOS 26, *)
public struct AppleTranscriber: CallTranscriber {
    public enum Engine: Sendable {
        case speech, dictation
    }

    public let engine: Engine
    public let locale: Locale

    public init(engine: Engine, locale: Locale) {
        self.engine = engine
        self.locale = locale
    }

    public var name: String { "Apple \(engine == .speech ? "Speech" : "Dictation") \(locale.identifier)" }

    private func module() -> any SpeechModule {
        switch engine {
        case .speech: SpeechTranscriber(locale: locale, preset: .transcription)
        case .dictation: DictationTranscriber(locale: locale, preset: .longDictation)
        }
    }

    public func status() async -> AssetInventory.Status {
        await AssetInventory.status(forModules: [module()])
    }

    public func install() async throws {
        try await AssetInventory.assetInstallationRequest(supporting: [module()])?.downloadAndInstall()
    }

    public func transcribe(_ audio: URL) async throws -> String {
        switch await status() {
        case .unsupported: throw TranscriberError.unsupported(name)
        case .supported, .downloading: throw TranscriberError.notInstalled(name)
        case .installed: break
        @unknown default: throw TranscriberError.unsupported(name)
        }
        let file = try AVAudioFile(forReading: audio)
        switch engine {
        case .speech:
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            return try await Self.run(file, module: module, results: module.results) { String($0.text.characters) }
        case .dictation:
            let module = DictationTranscriber(locale: locale, preset: .longDictation)
            return try await Self.run(file, module: module, results: module.results) { String($0.text.characters) }
        }
    }

    private static func run<Results: AsyncSequence & Sendable>(
        _ file: AVAudioFile, module: any SpeechModule, results: Results,
        text: @escaping @Sendable (Results.Element) -> String
    ) async throws -> String where Results.Element: Sendable {
        let collected = Task { try await results.reduce(into: [String]()) { $0.append(text($1)) } }
        let analyzer = SpeechAnalyzer(modules: [module])
        if let end = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected.value.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

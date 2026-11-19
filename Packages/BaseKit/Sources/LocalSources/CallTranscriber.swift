import AVFoundation
import Foundation
import Speech

/// Turns one call track into text, on this Mac. Engines are compared by word error rate on the founder's own calls
/// before one is used (research 05's bake-off).
public protocol CallTranscriber: Sendable {
    var name: String { get }
    func transcribe(_ audio: URL) async throws -> String
}

public enum TranscriberError: Error, Equatable {
    /// The engine does not support the locale at all.
    case unsupported(String)
    /// The locale is supported but its on-device model is not installed. Installing downloads it from Apple.
    case notInstalled(String)
}

/// Apple's on-device speech engines (macOS 26): SpeechTranscriber (en-IN and 29 other locales) and DictationTranscriber
/// (hi-IN among others). Neither mixes Hindi and English in one session (research 05), which the bake-off measures.
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

    /// Whether the model is on this Mac. Never downloads: installing is the founder's act (`install()`).
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

    /// Feeds the whole file to the analyzer and joins the module's final results.
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

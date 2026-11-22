import Foundation
import LocalSources
import WorkbenchCore

@available(macOS 26, *)
func bakeoff() async throws {
    let arguments = CommandLine.arguments.dropFirst()
    guard let path = arguments.first(where: { !$0.hasPrefix("--") }) else {
        print("Usage: transcribe-bakeoff <folder with call.m4a and call.txt pairs> [--install]")
        exit(2)
    }
    let install = arguments.contains("--install")
    let folder = URL(filePath: path)
    let audio = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
        .filter { ["m4a", "wav", "aiff", "caf"].contains($0.pathExtension.lowercased()) }
        .filter {
            FileManager.default.fileExists(atPath: $0.deletingPathExtension().appendingPathExtension("txt").path)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    print("\(audio.count) calls with a reference transcript in \(folder.path)")
    let engines: [AppleTranscriber] = [
        AppleTranscriber(engine: .speech, locale: Locale(identifier: "en-IN")),
        AppleTranscriber(engine: .speech, locale: Locale(identifier: "en-US")),
        AppleTranscriber(engine: .dictation, locale: Locale(identifier: "hi-IN")),
    ]
    for engine in engines {
        if install, await engine.status() == .supported {
            print("\(engine.name): downloading Apple's on-device model…")
            try await engine.install()
        }
        var scores: [WordErrorRate] = []
        let started = Date()
        for file in audio {
            let reference = try String(
                contentsOf: file.deletingPathExtension().appendingPathExtension("txt"), encoding: .utf8)
            do {
                let heard = try await engine.transcribe(file)
                let score = WordErrorRate(reference: reference, transcript: heard)
                scores.append(score)
                print(
                    "  \(engine.name) · \(file.lastPathComponent): WER \(String(format: "%.1f%%", score.rate * 100)) — \(heard.prefix(80))"
                )
            } catch {
                print("  \(engine.name): \(error)")
                break
            }
        }
        guard !scores.isEmpty else { continue }
        let pooled = WordErrorRate.pooled(scores)
        print(
            "\(engine.name): pooled WER \(String(format: "%.1f%%", pooled.rate * 100)) over \(pooled.referenceWords) words, \(String(format: "%.1f", Date().timeIntervalSince(started))) s"
        )
    }
    print(
        "Not in this run: WhisperKit with Oriserve Hindi2Hinglish (research 05's top candidate) needs a 0.6–0.9 GB model download."
    )
}

if #available(macOS 26, *) {
    try await bakeoff()
} else {
    print("Needs macOS 26.")
    exit(1)
}

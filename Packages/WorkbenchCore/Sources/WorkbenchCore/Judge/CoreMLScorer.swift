import CoreML
import CryptoKit
import Foundation

/// How a verifier family reads a premise and a claim. Each family was trained on one text form, and the form is part
/// of the model: a change to it is a different model.
public enum VerifierRecipe: String, Codable, Sendable, CaseIterable {
    /// FactCG-DeBERTa-v3-Large: the premise and the claim in the instruction text of its training (two labels).
    case factcg
    /// MiniCheck-Flan-T5-Large: `predict: premise</s>claim`, and the answer is read from the first decoder step.
    case minicheck

    func text(premise: String, claim: String) -> String {
        switch self {
        case .factcg:
            """
            \(premise)

            Choose your answer: based on the paragraph above can we conclude that "\(claim)"?

            OPTIONS:
            - Yes
            - No
            I think the answer is
            """
        case .minicheck: "predict: \(premise)</s>\(claim)"
        }
    }
}

/// What a model folder says about itself: the recipe and the hash of the model package it was made with.
public struct GroundingManifest: Codable, Sendable, Equatable {
    public var name: String
    public var recipe: VerifierRecipe
    public var packageDigest: String
    public var sequenceLength: Int
    /// The cuts that turn a score into a verdict, chosen on dev marks and frozen with the model.
    public var band: ScoreBand?

    static func read(from folder: URL) throws -> GroundingManifest {
        try JSONDecoder().decode(
            GroundingManifest.self, from: Data(contentsOf: folder.appending(path: "manifest.json")))
    }
}

public enum GroundingModelError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case checksumMismatch(expected: String, found: String)
    case badOutput

    public var description: String {
        switch self {
        case .missing(let name): "The verifier folder has no \(name)."
        case .checksumMismatch: "The verifier model does not match its recorded checksum, so it was not loaded."
        case .badOutput: "The verifier model gave an output that is not two numbers."
        }
    }
}

/// The digest of a folder: the SHA-256 of one line per file, `relative path`, a tab, and the file's SHA-256, sorted by
/// path. A model package is a folder, so this is how a manifest names it.
public enum FolderDigest {
    public static func sha256(of folder: URL) throws -> String {
        let root = folder.resolvingSymlinksInPath()
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { throw GroundingModelError.missing(folder.lastPathComponent) }
        var lines: [String] = []
        for case let file as URL in files {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            lines.append("\(file.path.dropFirst(root.path.count + 1))\t\(try fileDigest(file))")
        }
        return SHA256.hash(data: Data(lines.sorted().map { $0 + "\n" }.joined().utf8)).hex
    }

    public static func fileDigest(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 22), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().hex
    }
}

extension SHA256Digest {
    fileprivate var hex: String { map { String(format: "%02x", $0) }.joined() }
}

/// An on-device support scorer: a Core ML model and its tokenizer, loaded from a model folder. The folder holds
/// `manifest.json`, `tokenizer.json` and `model.mlpackage` (compiled once to `model.mlmodelc` beside it). The package
/// is checked against the manifest's digest before it is loaded. No network and no Python.
public actor CoreMLScorer: SupportScorer {
    public nonisolated let identity: GroundingIdentity
    private let model: MLModel
    private let tokenizer: UnigramTokenizer
    private let recipe: VerifierRecipe
    private let sequenceLength: Int

    public static func load(folder: URL, computeUnits: MLComputeUnits = .cpuAndGPU) async throws -> CoreMLScorer {
        let manifest = try GroundingManifest.read(from: folder)
        let package = folder.appending(path: "model.mlpackage")
        guard FileManager.default.fileExists(atPath: package.path) else {
            throw GroundingModelError.missing("model.mlpackage")
        }
        let found = try FolderDigest.sha256(of: package)
        guard found == manifest.packageDigest else {
            throw GroundingModelError.checksumMismatch(expected: manifest.packageDigest, found: found)
        }
        let compiled = folder.appending(path: "model.mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
            let made = try await MLModel.compileModel(at: package)
            try FileManager.default.moveItem(at: made, to: compiled)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        return CoreMLScorer(
            model: try MLModel(contentsOf: compiled, configuration: configuration),
            tokenizer: try UnigramTokenizer(contentsOf: folder.appending(path: "tokenizer.json")),
            manifest: manifest)
    }

    private init(model: MLModel, tokenizer: UnigramTokenizer, manifest: GroundingManifest) {
        self.model = model
        self.tokenizer = tokenizer
        recipe = manifest.recipe
        sequenceLength = manifest.sequenceLength
        identity = GroundingIdentity(
            name: manifest.name, weights: manifest.packageDigest, parameters: "s\(manifest.sequenceLength)")
    }

    /// The best support over the chunks of the premise: a claim is supported when one chunk supports it.
    public func support(of claim: String, premise: String) async throws -> Double {
        let chunks = PremiseChunker.chunks(of: premise) { fits(recipe.text(premise: $0, claim: claim)) }
        var best = 0.0
        for chunk in chunks { best = max(best, try score(recipe.text(premise: chunk, claim: claim))) }
        return best
    }

    /// The ids of the text, for a parity check against the reference tokenizer.
    public func tokenIDs(premise: String, claim: String) -> [Int32] {
        tokenizer.encode(recipe.text(premise: premise, claim: claim))
    }

    private func fits(_ text: String) -> Bool { tokenizer.encode(text).count <= sequenceLength }

    private func score(_ text: String) throws -> Double {
        var ids = tokenizer.encode(text)
        if ids.count > sequenceLength { ids = Array(ids.prefix(sequenceLength)) }
        let input = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
        let mask = try MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32)
        for position in 0..<sequenceLength {
            input[position] = NSNumber(value: position < ids.count ? ids[position] : tokenizer.padID)
            mask[position] = NSNumber(value: position < ids.count ? 1 : 0)
        }
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: input), "attention_mask": MLFeatureValue(multiArray: mask),
        ])
        let output = try model.prediction(from: features)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue, logits.count == 2 else {
            throw GroundingModelError.badOutput
        }
        let (unsupported, supported) = (logits[0].doubleValue, logits[1].doubleValue)
        let probability = 1 / (1 + exp(unsupported - supported))
        guard probability.isFinite else { throw GroundingModelError.badOutput }
        return probability
    }
}

extension CoreMLScorer {
    /// The verifier a model folder describes: its scorer read through the band its manifest holds.
    public static func verifier(folder: URL, computeUnits: MLComputeUnits = .cpuAndGPU) async throws -> BandedGrounding
    {
        guard let band = try GroundingManifest.read(from: folder).band else {
            throw GroundingModelError.missing("band in manifest.json")
        }
        return BandedGrounding(scorer: try await load(folder: folder, computeUnits: computeUnits), band: band)
    }
}

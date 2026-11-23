import Foundation

/// A SentencePiece Unigram tokenizer read from a Hugging Face `tokenizer.json`: the vocabulary with its scores, the
/// special tokens, and the template that wraps a single text. It serves both verifier families (DeBERTa-v3 and
/// Flan-T5), whose files differ only in data. The text is normalised with NFKC and single spaces, a space before each
/// word is the mark `▁`, and each word is cut by the best-scoring path of pieces (Viterbi), as the reference does.
struct UnigramTokenizer: Sendable {
    struct Piece: Sendable {
        var id: Int32
        var score: Double
    }

    struct FileError: Error, CustomStringConvertible {
        var description: String
    }

    private let pieces: [String: Piece]
    private let longestPiece: Int
    private let unknown: Piece
    private let specials: [(literal: String, id: Int32)]
    private let prefix: [Int32]
    private let suffix: [Int32]
    let padID: Int32

    private static let wordMark: Character = "\u{2581}"
    /// The score below the lowest piece that an unknown character gets (the reference's penalty).
    private static let unknownPenalty = 10.0

    init(contentsOf file: URL) throws {
        guard let root = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any],
            let model = root["model"] as? [String: Any], model["type"] as? String == "Unigram",
            let vocabulary = model["vocab"] as? [[Any]], let unknownID = model["unk_id"] as? Int
        else { throw FileError(description: "\(file.lastPathComponent) is not a Unigram tokenizer file") }
        let added = (root["added_tokens"] as? [[String: Any]] ?? []).compactMap { entry -> (String, Int32)? in
            guard entry["special"] as? Bool == true, let content = entry["content"] as? String,
                let id = entry["id"] as? Int
            else { return nil }
            return (content, Int32(id))
        }
        let special = Set(added.map(\.1))
        var table: [String: Piece] = [:]
        var lowest = 0.0
        var longest = 1
        for (index, entry) in vocabulary.enumerated() {
            guard let text = entry.first as? String, let score = (entry.last as? NSNumber)?.doubleValue else {
                throw FileError(description: "vocabulary entry \(index) is not a piece and a score")
            }
            lowest = min(lowest, score)
            guard !special.contains(Int32(index)) else { continue }
            table[text] = Piece(id: Int32(index), score: score)
            longest = max(longest, text.unicodeScalars.count)
        }
        pieces = table
        longestPiece = longest
        unknown = Piece(id: Int32(unknownID), score: lowest - Self.unknownPenalty)
        specials = added.sorted { $0.0.count > $1.0.count }.map { (literal: $0.0, id: $0.1) }
        padID = added.first { $0.0.lowercased().contains("pad") }?.1 ?? 0
        (prefix, suffix) = Self.template(of: root["post_processor"] as? [String: Any])
    }

    /// The ids of a text, wrapped in the template of the file (`[CLS] text [SEP]` or `text </s>`).
    func encode(_ text: String) -> [Int32] { prefix + body(of: text) + suffix }

    /// The ids of a text with no template. A special token written in the text, such as `</s>`, is one id.
    func body(of text: String) -> [Int32] {
        var ids: [Int32] = []
        var rest = Substring(text)
        while !rest.isEmpty {
            let next = specials.compactMap { special in rest.range(of: special.literal).map { ($0, special.id) } }
                .min { $0.0.lowerBound < $1.0.lowerBound }
            guard let (range, id) = next else {
                ids += words(of: String(rest))
                break
            }
            ids += words(of: String(rest[..<range.lowerBound]))
            ids.append(id)
            rest = rest[range.upperBound...]
        }
        return ids
    }

    private func words(of text: String) -> [Int32] {
        let normal = Self.normalised(text)
        guard !normal.isEmpty else { return [] }
        let marked = String(Self.wordMark) + normal.replacingOccurrences(of: " ", with: String(Self.wordMark))
        var ids: [Int32] = []
        var word = ""
        for character in marked {
            if character == Self.wordMark, !word.isEmpty {
                ids += cut(word)
                word = ""
            }
            word.append(character)
        }
        return ids + cut(word)
    }

    /// The best-scoring cut of one word into pieces. A character no piece covers is one unknown, and neighbours merge.
    private func cut(_ word: String) -> [Int32] {
        let scalars = Array(word.unicodeScalars)
        var best = [Double](repeating: -.infinity, count: scalars.count + 1)
        var from = [Int](repeating: 0, count: scalars.count + 1)
        var chosen = [Piece](repeating: unknown, count: scalars.count + 1)
        best[0] = 0
        for start in 0..<scalars.count where best[start] > -.infinity {
            var coversOne = false
            for length in 1...min(longestPiece, scalars.count - start) {
                var text = String.UnicodeScalarView()
                text.append(contentsOf: scalars[start..<start + length])
                guard let piece = pieces[String(text)] else { continue }
                coversOne = coversOne || length == 1
                relax(&best, &from, &chosen, start: start, length: length, piece: piece)
            }
            if !coversOne { relax(&best, &from, &chosen, start: start, length: 1, piece: unknown) }
        }
        var ids: [Int32] = []
        var end = scalars.count
        while end > 0 {
            let piece = chosen[end]
            if piece.id != unknown.id || ids.last != unknown.id { ids.append(piece.id) }
            end = from[end]
        }
        return ids.reversed()
    }

    private func relax(
        _ best: inout [Double], _ from: inout [Int], _ chosen: inout [Piece], start: Int, length: Int, piece: Piece
    ) {
        let score = best[start] + piece.score
        guard score > best[start + length] else { return }
        best[start + length] = score
        from[start + length] = start
        chosen[start + length] = piece
    }

    private static func normalised(_ text: String) -> String {
        let compatible = text.precomposedStringWithCompatibilityMapping
        let spaced = compatible.unicodeScalars.map { $0.properties.isWhitespace ? " " : Character($0) }
        return String(spaced).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    /// The ids before and after a single text, from the file's `TemplateProcessing`.
    private static func template(of processor: [String: Any]?) -> ([Int32], [Int32]) {
        guard let processor, let single = processor["single"] as? [[String: Any]],
            let known = processor["special_tokens"] as? [String: [String: Any]]
        else { return ([], []) }
        var (before, after) = ([Int32](), [Int32]())
        var seenText = false
        for step in single {
            if step["Sequence"] != nil {
                seenText = true
            } else if let token = (step["SpecialToken"] as? [String: Any])?["id"] as? String,
                let ids = known[token]?["ids"] as? [Int]
            {
                if seenText { after += ids.map(Int32.init) } else { before += ids.map(Int32.init) }
            }
        }
        return (before, after)
    }
}

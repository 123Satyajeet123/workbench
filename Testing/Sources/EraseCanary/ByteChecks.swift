import Foundation

/// The byte scan of one scene at one moment: every word that must be gone has no byte left, and every word that must
/// stay is found, so a scan that finds nothing is shown to be able to find.
struct ByteChecks {
    let scene: Scene
    let trigger: Trigger
    let findings: Findings

    func run(stage: String) {
        let scanned = ByteScan.files(under: scene.directory).map {
            "\($0.lastPathComponent) \((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)"
        }
        print("     \(trigger.rawValue) / \(stage): scanning \(scanned.sorted())")
        for (name, word) in scene.words.all {
            let hits = ByteScan.hits(of: word, under: scene.directory)
            if trigger.gone.contains(name) {
                for hit in hits + fragmentHits(of: word, outside: hits) {
                    findings.leak(
                        "\(trigger.rawValue) / \(stage): \(name) in \(hit.file) at byte \(hit.offset) (\(hit.encoding)), \(hit.place)"
                    )
                }
            } else {
                findings.expect(
                    hits.contains { $0.encoding == "utf8" },
                    "\(trigger.rawValue) / \(stage): the word that stays (\(name)) is found in \(Set(hits.map(\.file)).sorted())"
                )
            }
        }
    }

    /// Half a word at either end that stands alone: an index may keep the start of a word it dropped.
    private func fragmentHits(of word: String, outside whole: [Hit]) -> [Hit] {
        let halves = [String(word.prefix(12)), String(word.suffix(12))]
        return halves.flatMap { ByteScan.hits(of: $0, under: scene.directory) }.filter { fragment in
            !whole.contains {
                $0.file == fragment.file && $0.encoding == fragment.encoding
                    && (0..<word.utf8.count * 2).contains(fragment.offset - $0.offset)
            }
        }.map { Hit(file: $0.file, offset: $0.offset, encoding: $0.encoding + " fragment", place: $0.place) }
    }
}

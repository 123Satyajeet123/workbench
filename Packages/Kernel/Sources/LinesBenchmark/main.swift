// Source: built (M1 step 1 gate S9: median time of line_id over 100k lines).
// Run: swift run -c release LinesBenchmark

import Lines

/// Texts like chat lines: 4 to 20 words drawn from Latin, Hinglish and Devanagari words, with an NFD letter, a
/// double space and a zero width space in some of them. A fixed linear congruential sequence makes every run equal.
func makeTexts(count: Int) -> [String] {
    let words = [
        "Kal", "deck", "bhejo", "5", "baje", "tak", "meeting", "hai", "हिन्दी", "में", "ज़रूरी", "Cafe\u{301}", "ok",
        "investor", "call", "\u{1F44D}", "term", "sheet", "क्‍ष", "theek",
    ]
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }
    return (0..<count).map { _ in
        (0..<(4 + next(17))).map { _ in words[next(words.count)] + (next(10) == 0 ? "  \u{200B}" : "") }
            .joined(separator: " ")
    }
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

let count = 100_000
let runs = 11
let texts = makeTexts(count: count)
let keys = try (0..<count).map {
    try EntityKey.whatsAppGroup(
        chat: "120363041234567890@g.us", author: .member("91@s.whatsapp.net"), stanzaID: "3EB0\($0)")
}
let clock = ContinuousClock()
var checksum: UInt8 = 0
var lineRuns: [Double] = []
var screenRuns: [Double] = []
for _ in 0..<runs {
    let start = clock.now
    for index in 0..<count {
        checksum ^= Line(entity: keys[index], text: texts[index], readerVersion: "wa 1").id.bytes[0]
    }
    lineRuns.append(milliseconds(clock.now - start))
    let screenStart = clock.now
    for read in stride(from: 0, to: count, by: 50) {
        let lines = try Line.screen(
            container: "app place", texts: Array(texts[read..<(read + 50)]), readerVersion: "ax 1")
        for line in lines { checksum ^= line.id.bytes[0] }
    }
    screenRuns.append(milliseconds(clock.now - screenStart))
}
let averageScalars = Double(texts.map(\.unicodeScalars.count).reduce(0, +)) / Double(count)
print(
    "line_id over \(count) chat lines (mean \(averageScalars) scalars), \(runs) runs: median \(median(lineRuns)) ms "
        + "per run, \(median(lineRuns) * 1000 / Double(count)) us per line; min \(lineRuns.min()!) ms, max \(lineRuns.max()!) ms"
)
print(
    "Line.screen over \(count) texts in reads of 50, \(runs) runs: median \(median(screenRuns)) ms per run, "
        + "\(median(screenRuns) * 1000 / Double(count)) us per line; check \(checksum)"
)

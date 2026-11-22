import Foundation
import Kernel
import Lines
import PropertyBased

/// Random inputs for the line identity laws. Texts mix Latin, Devanagari (with nukta letters that NFC keeps
/// decomposed), a singleton decomposition (the Ohm sign), emoji and digits, each spelled NFC or NFD at random.
enum LineWorld {
    /// One letter or syllable in two canonically equal spellings.
    static let pieces: [(String, String)] = [
        ("\u{E9}", "e\u{301}"), ("\u{C5}", "A\u{30A}"), ("\u{2126}", "\u{3A9}"), ("\u{95B}", "\u{91C}\u{93C}"),
        ("\u{939}\u{93F}", "\u{939}\u{93F}"), ("k", "k"), ("Q", "Q"), ("5", "5"), ("\u{1F44D}", "\u{1F44D}"),
    ]

    static let words = ["Kal", "deck", "bhejo", "\u{939}\u{93F}\u{928}\u{94D}\u{926}\u{940}", "Caf\u{E9}", "5", "baje"]
    static let spaces = [" ", "  ", "\t", "\n", "\u{A0}", "\u{3000}", "\u{2000}", "\r\n"]
    static let invisibles = [
        "\u{200B}", "\u{2060}", "\u{FEFF}", "\u{AD}", "\u{200E}", "\u{200F}", "\u{202B}", "\u{2066}", "\u{61C}",
    ]
    static let zones = ["UTC", "Asia/Kolkata", "America/Los_Angeles", "Australia/Adelaide", "Asia/Kathmandu"]

    static func spelledPair(_ rng: inout any SeededRandomNumberGenerator) -> (String, String) {
        let indices = (0..<Int.random(in: 1...6, using: &rng)).map { _ in
            Int.random(in: 0..<pieces.count, using: &rng)
        }
        func spell(_ rng: inout any SeededRandomNumberGenerator) -> String {
            indices.map { Bool.random(using: &rng) ? pieces[$0].0 : pieces[$0].1 }.joined()
        }
        return (spell(&rng), spell(&rng))
    }

    static func sentence(_ rng: inout any SeededRandomNumberGenerator) -> [String] {
        (0..<Int.random(in: 1...5, using: &rng)).map { _ in words.randomElement(using: &rng) ?? "" }
    }

    static func identifier(_ rng: inout any SeededRandomNumberGenerator) -> String {
        String((0..<Int.random(in: 1...8, using: &rng)).map { _ in "ab@.9Z\u{E9}".randomElement(using: &rng)! })
    }

    /// Two spellings of one text that differ only in canonical equivalence.
    static let canonicalPair = Generator(run: { rng in spelledPair(&rng) })

    /// One sentence written twice: with random runs of white space (also at the ends) and invisible format characters
    /// put between any two scalars, so also between a letter and its combining mark.
    static let spacedPair = Generator(run: { rng in
        let words = sentence(&rng)
        func messy(_ rng: inout any SeededRandomNumberGenerator) -> String {
            let edge = { (rng: inout any SeededRandomNumberGenerator) in
                Bool.random(using: &rng) ? spaces.randomElement(using: &rng)! : ""
            }
            let joined = words.joined(separator: spaces.randomElement(using: &rng)!)
            var scalars = String.UnicodeScalarView()
            for scalar in joined.unicodeScalars {
                if Int.random(in: 0..<4, using: &rng) == 0 {
                    scalars += invisibles.randomElement(using: &rng)!.unicodeScalars
                }
                scalars.append(scalar)
            }
            return edge(&rng) + String(scalars) + edge(&rng)
        }
        return (words.joined(separator: " "), messy(&rng))
    })

    /// A text and a second text that differs in meaning by one change: a letter's case, a joiner inside a
    /// Devanagari conjunct, another word, or one word more.
    static let changedText = Generator(run: { rng in
        let words = sentence(&rng) + ["\u{915}\u{94D}\u{937}"]
        var changed = words
        switch Int.random(in: 0..<4, using: &rng) {
        case 0: changed[changed.count - 2] = flipCase(changed[changed.count - 2])
        case 1: changed[changed.count - 1] = "\u{915}\u{94D}\u{200D}\u{937}"
        case 2: changed[0] = changed[0] == "deck" ? "Deck" : "deck"
        default: changed.append("baje")
        }
        return (words.joined(separator: " "), changed.joined(separator: " "))
    })

    static func flipCase(_ word: String) -> String {
        guard let first = word.first(where: \.isLetter), first.isASCII else { return word + "X" }
        let flipped = first.isUppercase ? first.lowercased() : first.uppercased()
        return word.replacingCharacters(in: word.firstIndex(of: first)!...word.firstIndex(of: first)!, with: flipped)
    }

    /// Any text, for the normalization laws.
    static let anyText = Generator(run: { rng in
        let all = pieces.flatMap { [$0.0, $0.1] } + spaces + invisibles + ["\u{200D}", "\u{200C}", "\u{301}"]
        return (0..<Int.random(in: 0...10, using: &rng)).map { _ in all.randomElement(using: &rng)! }.joined()
    })

    /// Two entity keys that differ in exactly one way. Half of the cases move the boundary between the chat and the
    /// stanza id, so the two keys hold the same characters in the same order.
    static let changedEntity = Generator(run: { rng in
        let joined = identifier(&rng) + identifier(&rng) + "x"
        let text = sentence(&rng).joined(separator: " ")
        func direct(cut: Int, fromMe: Bool = false, occurrence: UInt32 = 0) -> EntitySpec {
            .direct(
                chat: String(joined.prefix(cut)), fromMe: fromMe, stanza: String(joined.dropFirst(cut)),
                occurrence: occurrence)
        }
        let cut = Int.random(in: 1..<joined.count, using: &rng)
        let base = direct(cut: cut)
        let group = joined + "@g.us"
        switch Int.random(in: 0..<11, using: &rng) {
        case 0...3 where joined.count > 2:
            let other = (cut % (joined.count - 1)) + 1
            return (base, direct(cut: other), text)
        case 4: return (base, direct(cut: cut, occurrence: 1), text)
        case 5:
            let member = identifier(&rng)
            return (
                EntitySpec.group(chat: group, author: nil, stanza: "s"),
                .group(chat: group, author: member, stanza: "s"), text
            )
        case 6:
            let member = identifier(&rng)
            return (
                EntitySpec.group(chat: group, author: member, stanza: "s"),
                .group(chat: group, author: member + "0", stanza: "s"), text
            )
        case 7: return (EntitySpec.gmail(id: joined), EntitySpec.gmail(id: joined + "0"), text)
        case 8:
            let at = Int64.random(in: 0...4_000_000_000_000, using: &rng)
            return (EntitySpec.calendar(id: joined, millis: at), EntitySpec.calendar(id: joined, millis: at + 1), text)
        case 9:
            return (
                EntitySpec.screen(container: joined, ordinal: 0), EntitySpec.screen(container: joined, ordinal: 1), text
            )
        default: return (base, direct(cut: cut, fromMe: true), text)
        }
    })

    /// One read of a screen container: texts drawn with repeats, each repeat spelled NFC or NFD at random, and a
    /// scroll window (a contiguous part of the read).
    static let screenRead = Generator(run: { rng in
        let distinct = (0..<Int.random(in: 1...3, using: &rng)).map { _ in spelledPair(&rng) }
        let read = (0..<Int.random(in: 1...8, using: &rng)).map { _ in
            let pick = distinct.randomElement(using: &rng)!
            return Bool.random(using: &rng) ? pick.0 : pick.1
        }
        let start = Int.random(in: 0..<read.count, using: &rng)
        let end = Int.random(in: start..<read.count, using: &rng)
        return (read, read.shuffled(using: &rng), Array(read[start...end]))
    })

    /// An instant and two time zones a reader might have resolved it in.
    static let instantInTwoZones = Generator(run: { rng in
        let seconds = Int64.random(in: 0...4_000_000_000, using: &rng)
        return (seconds * 1000, zones.randomElement(using: &rng)!, zones.randomElement(using: &rng)!)
    })

    /// A view: two or more different line ids in reading order, and the same ids in another order.
    static let reorderedView = Generator(run: { rng in
        let ids = (UInt8.min...UInt8.max).shuffled(using: &rng).prefix(Int.random(in: 2...6, using: &rng))
        let lines = ids.map { LineID(bytes: Array(repeating: $0, count: LineID.count))! }
        var other = lines.shuffled(using: &rng)
        if other == lines { other.swapAt(0, 1) }
        return (lines, other)
    })
}

/// The fields of an entity key, kept apart so a wrong implementation can be written over them.
enum EntitySpec: Sendable {
    case direct(chat: String, fromMe: Bool, stanza: String, occurrence: UInt32)
    /// A group message; a nil author is me.
    case group(chat: String, author: String?, stanza: String)
    case gmail(id: String)
    case calendar(id: String, millis: Int64)
    case screen(container: String, ordinal: UInt32)

    func key(text: String) throws -> EntityKey {
        switch self {
        case .direct(let chat, let fromMe, let stanza, let occurrence):
            try .whatsAppDirect(chat: chat, fromMe: fromMe, stanzaID: stanza, occurrence: occurrence)
        case .group(let chat, let author, let stanza):
            try .whatsAppGroup(chat: chat, author: author.map { .member($0) } ?? .me, stanzaID: stanza)
        case .gmail(let id): try .gmail(messageID: id)
        case .calendar(let id, let millis): try .calendar(externalID: id, occurrence: UTCInstant(milliseconds: millis))
        case .screen(let container, let ordinal):
            try .screen(container: container, content: ContentHash(text: text), ordinal: ordinal)
        }
    }

    /// The fields one after another with no length or separator: the naive key.
    var concatenated: String {
        switch self {
        case .direct(let chat, let fromMe, let stanza, let occurrence): chat + stanza + "\(fromMe)\(occurrence)"
        case .group(let chat, let author, let stanza): chat + (author ?? "") + stanza
        case .gmail(let id): id
        case .calendar(let id, let millis): id + "\(millis)"
        case .screen(let container, let ordinal): container + "\(ordinal)"
        }
    }
}

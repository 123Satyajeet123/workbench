import Foundation
import Kernel
import Synchronization
import WorkbenchCore

/// Turns synthetic letters into the messages the Gmail extension sends the native host, and gives them to the host's own
/// entry point, so a synthetic mail is kept by exactly the code that keeps a real one.
struct MailFeed {
    /// The Gmail account of the synthetic partner, which the page names as its own account.
    static let account = "meera.rao@northlake-capital.example.com"
    static let label = "Deals"
    static let browser = "com.google.Chrome"

    let owner: Result<PersonID, any Error>

    /// The frames one letter makes: the message, then each attached deck in chunks.
    static func frames(for letter: Letter) throws -> Data {
        let context = MailContext(
            browser: browser, url: "https://mail.google.com/mail/u/0/#label/\(label)/\(letter.thread)",
            label: label, threadId: letter.thread, messageId: letter.message)
        let message = MailMessage(
            context: context, sender: letter.sender, recipients: letter.recipients, account: account,
            sent: letter.sent.timeIntervalSince1970, text: letter.text, quoted: letter.quoted,
            attachments: letter.attachments.map(\.name))
        var frames = NativeMessage.frame(try JSONEncoder().encode(message))
        for deck in letter.attachments {
            let pieces = stride(from: 0, to: max(deck.data.count, 1), by: DeckChunk.size).map {
                deck.data[$0..<min($0 + DeckChunk.size, deck.data.count)]
            }
            for (index, piece) in pieces.enumerated() {
                let chunk = DeckChunk(
                    context: context, name: deck.name, index: index, count: pieces.count,
                    data: piece.base64EncodedString())
                frames += NativeMessage.frame(try JSONEncoder().encode(chunk))
            }
        }
        return frames
    }

    /// How many letters the host kept, and how many of their decks it kept as lines.
    struct Kept: Equatable {
        var letters = 0
        var decks = 0
    }

    /// Keeps each letter at the minute it was sent, as if the partner opened the thread then: the store dates a line by
    /// when it first saw it, and the machines read a day's lines by that date.
    func keep(_ letters: [Letter], in store: Store, at clock: MovableClock) throws -> Kept {
        var kept = Kept()
        for letter in letters {
            clock.set(letter.sent)
            let replies = Self.replies(
                in: PageHost.receive(try Self.frames(for: letter), store: store, browser: Self.browser, owner: owner))
            kept.letters += replies.first?.kept == true ? 1 : 0
            kept.decks += replies.dropFirst().filter(\.kept).count
        }
        return kept
    }

    private static func replies(in data: Data) -> [PageHost.Reply] {
        var rest = data
        var replies: [PageHost.Reply] = []
        while let (message, consumed) = try? NativeMessage.first(in: rest) {
            if let reply = try? JSONDecoder().decode(PageHost.Reply.self, from: message) { replies.append(reply) }
            rest = rest.dropFirst(consumed)
        }
        return replies
    }
}

/// The days no synthetic source may reach: 23 Nov to 6 Dec 2026 is a held-out study, and nothing here may be dated in it.
struct HeldOutWindow {
    let start: Date
    let end: Date

    static let study: HeldOutWindow = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return HeldOutWindow(
            start: calendar.date(from: DateComponents(year: 2026, month: 11, day: 23))!,
            end: calendar.date(from: DateComponents(year: 2026, month: 12, day: 7))!)
    }()

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// The store's clock for a build: it reads the real time, except while the builder moves it to the time a letter was sent.
nonisolated final class MovableClock: Sendable {
    private let moved = Mutex<Date?>(nil)

    var now: Date { moved.withLock { $0 } ?? Date() }

    func set(_ date: Date) { moved.withLock { $0 = date } }

    func release() { moved.withLock { $0 = nil } }
}

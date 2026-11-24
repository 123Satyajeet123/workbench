import Foundation

@testable import WorkbenchCore

/// Inputs the removed word lists and guesses decided, taken from the existing synthetic fixtures of the tests of
/// `CallSource`, `CompanyName`, `EntityMatcher` and `MeetingMatch`, and a few in other languages. Each function returns
/// one line per input, so the lines of the old code (kept in `OldBehaviour`) and of the new code compare by line.
enum Behaviour {
    static let calls: [(app: String, bundleID: String, title: String, address: String)] = [
        (
            "Google Chrome", "com.google.Chrome", "Meet - Weekly sync - Google Chrome",
            "https://meet.google.com/abc-defg-hij"
        ),
        ("Google Chrome", "com.google.Chrome", "Meet - abc-defg-hij", "meet.google.com/abc-defg-hij"),
        ("Brave Browser", "com.brave.Browser", "Meet - Camera and microphone recording", "https://meet.google.com/x"),
        ("zoom.us", "us.zoom.xos", "Zoom Meeting", ""),
        ("Microsoft Teams", "com.microsoft.teams2", "Design review | Microsoft Teams", ""),
        ("WhatsApp", "net.whatsapp.WhatsApp", "WhatsApp", ""),
        ("Arc", "company.thebrowser.Browser", "Standup", "https://app.slack.com/huddle/T1/C2"),
        ("Arc", "company.thebrowser.Browser", "Inbox", "https://app.slack.com/client/T1"),
        ("Riverside", "fm.riverside", "Episode 4", ""),
        ("In person", "in-person", "", ""),
        ("Google Chrome", "com.google.Chrome", "साप्ताहिक बैठक - Google Meet", "https://meet.google.com/x"),
        ("Google Chrome", "com.google.Chrome", "Reunión semanal - Google Chrome", "https://meet.google.com/x"),
        ("zoom.us", "us.zoom.xos", "Zoom Workplace", ""),
    ]

    static func callLines() -> [String] {
        calls.map { row in
            let source = CallSource.identify(
                app: row.app, bundleID: row.bundleID, windowTitle: row.title, address: row.address)
            return "\(row.title) -> \(source.label) (call: \(source.isCall))"
        }
    }

    static let names = [
        "Bolt Pay Private Limited", "Bolt Pay Pvt. Ltd.", "Zoho Corporation Pvt Ltd", "Bolt Technologies Pvt Ltd",
        "Acme India", "Limited", "Ola", "Café & Co",
    ]

    static func nameLines() -> [String] {
        names.map { "\($0) -> normal [\(CompanyName.normal($0))] terms \(CompanyName.terms(name: $0, aliases: []))" }
    }

    private static func company(_ name: String, aliases: [String] = [], status: WatchedCompany.Status = .portfolio)
        -> WatchedCompany
    {
        WatchedCompany(id: name, name: name, aliases: aliases, domain: nil, status: status, isDeal: false)
    }

    private static func article(_ title: String, _ text: String = "x") -> NewsArticle {
        NewsArticle(
            id: 1, feed: "Inc42", url: URL(string: "https://inc42.com/a/1")!, title: title,
            published: Date(timeIntervalSince1970: 1_700_000_000), text: text)
    }

    static func newsLines() -> [String] {
        let scenarios: [(String, [WatchedCompany], NewsArticle)] = [
            (
                "legal name listed, brand in the news", [company("Bolt Pay Private Limited")],
                article("Bolt Pay lays off 40")
            ),
            (
                "brand listed, legal name in the news", [company("Bolt Pay")],
                article("Bolt Pay Private Limited lays off 40")
            ),
            (
                "descriptor listed, bare brand in the news", [company("Bolt Technologies Pvt Ltd")],
                article("Bolt raises seed")
            ),
            ("bare brand listed, descriptor in the news", [company("Bolt")], article("Bolt Technologies raises seed")),
            ("alias confirmed", [company("Bolt Pay", aliases: ["BoltX"])], article("BoltX raises seed")),
            (
                "two companies, one legal form apart",
                [company("Bolt Pay"), company("Bolt Pay Pvt Ltd", status: .passed)], article("Bolt Pay raises")
            ),
        ]
        return scenarios.map { name, watched, article in
            "\(name) -> \(EntityMatcher.candidates(in: article, among: watched).map(\.label))"
        }
    }

    static func meetingLines() -> [String] {
        let me = Meeting.Attendee(name: "Aditya", email: "aditya@fund.vc", isMe: true)
        let acme = DealIdentity(id: "d1", names: ["Acme Robotics", "Acme"], domains: ["acme-robots.io"])
        let beta = DealIdentity(id: "d2", names: ["Beta"], domains: ["beta.ai"])
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        func subjects(_ title: String, _ guests: [(String, String)]) -> [MeetingSubject] {
            let meeting = Meeting(
                id: "e", calendar: "c", title: title, start: at, end: at,
                attendees: [me] + guests.map { Meeting.Attendee(name: $0.0, email: $0.1) })
            return MeetingMatch.subjects(of: meeting, people: ["Asha Rao"], deals: [acme, beta])
        }
        return [
            ("guest at a domain the deal lists", "x@acme-robots.io"),
            ("guest at beta.com, deal named Beta", "x@beta.com"),
            ("guest at beta.co.uk, deal named Beta", "x@beta.co.uk"), ("guest at beta.ai, deal lists it", "x@beta.ai"),
            ("guest at gmail.com", "x@gmail.com"),
        ].map { name, email in "\(name) -> \(subjects("Intro", [("X", email)]))" }
    }
}

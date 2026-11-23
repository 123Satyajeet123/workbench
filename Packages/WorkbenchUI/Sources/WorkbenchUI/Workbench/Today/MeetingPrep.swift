import Foundation
import WorkbenchCore

/// What Workbench already knows about one person or deal in a meeting, every line from an existing fact, summary or
/// linked item. Nothing here is new text from a model.
struct Prep: Identifiable, Equatable {
    struct Quote: Equatable {
        var text: String
        var source: String
    }

    var subject: MeetingSubject
    var name: String
    var line: String?
    var stage: String?
    var facts: [Item]
    var quotes: [Quote]

    var id: String {
        switch subject {
        case .person(let name): "person:\(name)"
        case .deal(let id): "deal:\(id)"
        }
    }

    var isEmpty: Bool { line == nil && facts.isEmpty && quotes.isEmpty }
}

/// A meeting with the prep of each person or deal it matched. No prep means the meeting shows with no card.
struct MeetingCard: Identifiable, Equatable {
    var meeting: Meeting
    var preps: [Prep]

    var id: String { meeting.id }
}

enum MeetingPrep {
    static let quotesShown = 3

    static func cards(
        for meetings: [Meeting], groups: [FactGroup], rows: [SummaryRow], deals: [WorkObject], actions: [Item],
        now: Date
    ) -> [MeetingCard] {
        let people = Set(groups.map(\.name) + rows.map(\.subject)).subtracting([""])
        let identities = deals.map(DealIdentity.init)
        return meetings.map { meeting in
            let preps = MeetingMatch.subjects(of: meeting, people: people, deals: identities).compactMap {
                subject -> Prep? in
                let prep =
                    switch subject {
                    case .person(let name): person(name, groups: groups, rows: rows)
                    case .deal(let id): deals.first { $0.id == id }.map { deal($0, actions: actions, now: now) }
                    }
                return prep.flatMap { $0.isEmpty ? nil : $0 }
            }
            return MeetingCard(meeting: meeting, preps: preps)
        }
    }

    private static func person(_ name: String, groups: [FactGroup], rows: [SummaryRow]) -> Prep {
        Prep(
            subject: .person(name), name: name, line: rows.first { $0.subject == name }?.line.text, stage: nil,
            facts: groups.first { $0.name == name }?.open ?? [], quotes: [])
    }

    private static func deal(_ deal: WorkObject, actions: [Item], now: Date) -> Prep {
        let latest = deal.items.sorted { $0.item.day > $1.item.day }.prefix(quotesShown)
        return Prep(
            subject: .deal(deal.id), name: deal.title, line: nil, stage: deal.stageLabels.first,
            facts: actions.filter {
                $0[DealAction.dealField] == deal.id && $0.isOpen(in: DealAction.lifecycle, at: now)
            },
            quotes: latest.map {
                Prep.Quote(
                    text: $0.item.quote, source: "\($0.item.source?.capturedFrom ?? "another source") · \($0.item.day)")
            })
    }
}

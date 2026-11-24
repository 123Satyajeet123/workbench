import Evals
import Foundation
import WorkbenchCore

@testable import DemoBuild

/// What the generator knows about a line: whether it holds a fact, who wrote it and how long its text is. The audit's
/// answering person reads these labels.
struct LineLabel {
    let isFact: Bool
    let from: Member
    let length: Int
}

/// A synthetic team-chat day with its planted needles: the evidence the reader gets, for each needle the number of its
/// line, and the label of every line.
struct SyntheticDay {
    let day: WorkDay
    let evidence: EvidenceSet
    let needles: [(needle: Needle, line: Int64)]
    let labels: [Int64: LineLabel]

    var characters: Int { evidence.lines.map(\.line.count).reduce(0, +) }
    var factLines: [Int64] { labels.filter(\.value.isFact).map(\.key) }
}

/// Builds the probe's days from one seed: generated chatter up to a day length, background facts (the demo's script and
/// more invented lines) and needles, shuffled into one ordered chat per day. Pure: the same seed gives the same days.
enum SyntheticDays {
    typealias Said = (from: Member, text: String)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    static let dates = ["2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-16"]
    static let characters = 22_000...32_000
    static let backgroundPerDay = 7
    static let needlesPerDay = 8

    static var context: [String: [String]] {
        ["members": Member.allCases.map(\.rawValue), "founder": [Member.meera.rawValue]]
    }

    static func make(seed: UInt64, days count: Int = dates.count) -> [SyntheticDay] {
        var random = SeededGenerator(seed: seed)
        let background = (demoLines + moreBackground).shuffled(using: &random)
        let needles = Needle.all.shuffled(using: &random)
        return dates.prefix(count).enumerated().map { index, date in
            let facts = Array(background[index * backgroundPerDay..<(index + 1) * backgroundPerDay])
            let planted = Array(needles[index * needlesPerDay..<(index + 1) * needlesPerDay])
            let fixed = (facts + planted.map { ($0.from, $0.text) }).map { $0.from.rawValue.count + 2 + $0.text.count }
            let chatter = Chatter.lines(
                characters: Int.random(in: characters, using: &random) - fixed.reduce(0, +), using: &random)
            return compose(
                date: date, filler: (chatter.map { ($0, false) } + facts.map { ($0, true) }).shuffled(using: &random),
                needles: planted, random: &random)
        }
    }

    /// Puts each needle (after its question, with up to two chatter lines between) at a random place in the filler, then
    /// numbers and times the lines.
    private static func compose(
        date: String, filler: [(said: Said, isFact: Bool)], needles: [Needle], random: inout SeededGenerator
    ) -> SyntheticDay {
        typealias Line = (said: Said, isFact: Bool, needle: Needle?)
        var lines: [Line] = filler.map { ($0.said, $0.isFact, nil) }
        for needle in needles {
            let at = Int.random(in: 0...lines.count, using: &random)
            var unit: [Line] = [((needle.from, needle.text), true, needle)]
            if let question = needle.question {
                let gap = Chatter.lines(characters: Int.random(in: 0...40, using: &random), using: &random)
                unit = [((question.from, question.text), false, nil)] + gap.map { ($0, false, nil) } + unit
            }
            lines.insert(contentsOf: unit, at: at)
        }
        let day = WorkDay(containing: time(date, minutes: 12 * 60), calendar: calendar)
        let seconds = 15 * 3600 / max(lines.count, 1)
        let number = { (index: Int) in Int64(1001 + index) }
        let evidence = lines.enumerated().map { index, line in
            Evidence(
                id: number(index), start: time(date, minutes: 8 * 60).addingTimeInterval(Double(index * seconds)),
                line: "\(line.said.from.rawValue): \(line.said.text)", quotable: [line.said.text])
        }
        let labels = lines.enumerated().map { index, line in
            (number(index), LineLabel(isFact: line.isFact, from: line.said.from, length: line.said.text.count))
        }
        return SyntheticDay(
            day: day, evidence: EvidenceSet(lines: evidence, context: context),
            needles: lines.enumerated().compactMap { index, line in line.needle.map { ($0, number(index)) } },
            labels: Dictionary(uniqueKeysWithValues: labels))
    }

    private static func time(_ date: String, minutes: Int) -> Date {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        return calendar.date(
            from: DateComponents(
                year: parts[0], month: parts[1], day: parts[2], hour: minutes / 60, minute: minutes % 60))!
    }

    /// The demo's own synthetic chat, as background facts.
    static var demoLines: [Said] {
        SyntheticWhatsApp.script.map { line in
            let from: Member =
                switch line.from {
                case SyntheticWhatsApp.aditi?: .aditi
                case SyntheticWhatsApp.rohan?: .rohan
                default: .meera
                }
            return (from, line.text)
        }
    }

    static let moreBackground: [Said] = [
        (.rohan, "Ledgerwick ne updated MIS bhej diya, numbers ab match kar rahe hain."),
        (.kabir, "Tallyra ka ARR 1.8 crore confirm hua bank statement se."),
        (.nisha, "Dukanvault ka founder Mumbai shift ho raha hai next month."),
        (.meera, "Kistiwala pe hum pass kar rahe hain, final."),
        (.aditi, "Bolbhasha ka retention 38% month-3 pe hai."),
        (.kabir, "CRM migration 60% ho gaya."),
        (.rohan, "Quillrate ka reference call ho gaya, customer khush hai."),
        (.nisha, "Paynidhi ka deck shared folder me hai."),
        (.meera, "Suryabandh ko term sheet nahi denge jab tak margin clear nahi hota."),
        (.aditi, "Voltarth ke do angel investors se baat hui, dono positive hain."),
        (.kabir, "Fund admin ne Q2 statements bhej diye."),
        (.rohan, "Nidanwala ka cap table clean hai, koi issue nahi."),
        (.nisha, "Demo day ki list me 14 startups hain."),
        (.meera, "Bolbhasha pe IC 2 December ko hoga."),
        (.aditi, "Ledgerwick founder ne valuation 40 se 32 crore kar diya."),
        (.kabir, "Tallyra ne Series A ke liye ek aur fund se bhi baat shuru ki hai."),
        (.meera, "Ledgerwick ka next call Friday ko hai, sab log aana."),
        (.nisha, "Voltarth ne apna Q3 MIS share kar diya."),
    ]
}

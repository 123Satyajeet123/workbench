import Evals
import Foundation
import WorkbenchCore

@testable import DemoBuild

/// A synthetic team-chat day with its planted needles: the evidence the reader gets, for each needle the number of its
/// line, and the numbers of the background fact lines.
struct SyntheticDay {
    let day: WorkDay
    let evidence: EvidenceSet
    let needles: [(needle: Needle, line: Int64)]
    let background: Set<Int64>
}

/// Builds the probe's days from one seed: chatter, background facts (the demo's script and more invented lines) and
/// needles, shuffled into one ordered chat per day. Pure: the same seed gives the same days.
enum SyntheticDays {
    typealias Said = (from: Member, text: String)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }()

    static let dates = [
        "2026-11-09", "2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13", "2026-11-16", "2026-11-17", "2026-11-18",
    ]
    static let chatterPerDay = 30
    static let backgroundPerDay = 5
    static let needlesPerDay = 6

    static var context: [String: [String]] {
        ["members": Member.allCases.map(\.rawValue), "founder": [Member.meera.rawValue]]
    }

    static func make(seed: UInt64, days count: Int = dates.count) -> [SyntheticDay] {
        var random = SeededGenerator(seed: seed)
        let background = (demoLines + moreBackground).shuffled(using: &random)
        let needles = Needle.all.shuffled(using: &random)
        return dates.prefix(count).enumerated().map { index, date in
            let chatter = Array(chatterPool.shuffled(using: &random).prefix(chatterPerDay))
            let facts = background[index * backgroundPerDay..<(index + 1) * backgroundPerDay]
            let planted = needles[index * needlesPerDay..<(index + 1) * needlesPerDay]
            return compose(
                date: date, filler: (chatter + facts).shuffled(using: &random), facts: Set(facts.map(\.text)),
                needles: Array(planted), random: &random)
        }
    }

    /// Puts each needle (after its question, with up to one chatter line between) at a random place in the filler, then
    /// numbers and times the lines.
    private static func compose(
        date: String, filler: [Said], facts: Set<String>, needles: [Needle], random: inout SeededGenerator
    ) -> SyntheticDay {
        var lines: [(said: Said, needle: Needle?)] = filler.map { ($0, nil) }
        for needle in needles {
            let at = Int.random(in: 0...lines.count, using: &random)
            var unit: [(said: Said, needle: Needle?)] = [((needle.from, needle.text), needle)]
            if let question = needle.question {
                let gap = Bool.random(using: &random) ? [(said: chatterPool[0], needle: Needle?.none)] : []
                unit = [((question.from, question.text), nil)] + gap + unit
            }
            lines.insert(contentsOf: unit, at: at)
        }
        let day = WorkDay(containing: time(date, minutes: 12 * 60), calendar: calendar)
        let step = (11 * 60) / max(lines.count, 1)
        let evidence = lines.enumerated().map { index, line in
            Evidence(
                id: Int64(101 + index), start: time(date, minutes: 9 * 60 + index * step),
                line: "\(line.said.from.rawValue): \(line.said.text)", quotable: [line.said.text])
        }
        let planted = lines.enumerated().compactMap { index, line in
            line.needle.map { ($0, Int64(101 + index)) }
        }
        let background = evidence.filter { facts.contains($0.quotable[0]) }.map(\.id)
        return SyntheticDay(
            day: day, evidence: EvidenceSet(lines: evidence, context: context), needles: planted,
            background: Set(background))
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
    ]

    static let chatterPool: [Said] = [
        (.kabir, "👍"), (.aditi, "Good morning sab 🌞"), (.rohan, "gm"), (.nisha, "ok"), (.meera, "Theek hai"),
        (.rohan, "haha"), (.aditi, "😂😂"), (.nisha, "Lunch order kar rahe hain, kisko kya chahiye?"),
        (.kabir, "Mera ek paneer wrap"), (.rohan, "Same for me"), (.aditi, "Thanks!"), (.nisha, "Thank you 🙏"),
        (.kabir, "Noted"), (.rohan, "Sahi hai"), (.aditi, "Call pe hoon, baad me dekhti hoon"),
        (.kabir, "Traffic bahut hai aaj, 15 min late"), (.nisha, "Reached office"), (.rohan, "AC phir se band hai 🥵"),
        (.aditi, "https://www.livemint.com/companies/start-ups/funding-roundup-november"),
        (.aditi, "Ye article dekho, interesting hai"), (.kabir, "lol"), (.rohan, "Chai break?"), (.nisha, "Coming"),
        (.meera, "Nice"), (.meera, "Great work team"), (.kabir, "🔥"), (.rohan, "Happy birthday Nisha!! 🎂"),
        (.aditi, "Happy birthday 🎉"), (.nisha, "Thank you sab ❤️"), (.kabir, "Cake kab hai?"), (.nisha, "Shaam ko 😄"),
        (.rohan, "Ok cool"), (.aditi, "Haan"), (.kabir, "Nahi yaar"), (.nisha, "Weekend kaisa tha?"),
        (.rohan, "Badhiya, Lonavala gaye the"), (.aditi, "Pics bhejo"), (.rohan, "Sending"),
        (.kabir, "Meeting room 2 free hai?"), (.nisha, "Haan free hai"), (.aditi, "👌"), (.rohan, "Ek min"),
        (.rohan, "Back"), (.meera, "Rain bahut hai, sab dhyan se ghar jaana"), (.nisha, "Bye all, kal milte hain"),
        (.kabir, "Good night"), (.aditi, "Parking full hai aaj"), (.rohan, "Kisi ke paas Type C charger hai?"),
        (.nisha, "Mere paas hai, le lo"), (.kabir, "+1"), (.aditi, "Agreed 😂"), (.rohan, "Monday blues"),
        (.nisha, "Coffee machine theek ho gayi 🎉"),
    ]
}

import Evals

/// The uncited-line audit of D6 §4.2: a few uncited lines a day, drawn per stratum, each shown to the person as "does
/// this line hold a fact?". Here the generator's labels answer for the person. The estimate of missed fact lines is the
/// stratified one: the sum over strata of N_s x yes_s / n_s. Pure: the same seed gives the same draws.
enum Audit {
    enum Stratum: String, CaseIterable {
        case founderLong = "founder, long"
        case memberLong = "member, long"
        case founderShort = "founder, short"
        case memberShort = "member, short"

        init(_ label: LineLabel) {
            let isLong = label.length >= Audit.longFrom
            self =
                label.from.isFounder
                ? (isLong ? .founderLong : .founderShort) : (isLong ? .memberLong : .memberShort)
        }
    }

    /// Text of this many characters or more is long.
    static let longFrom = 80
    /// Cards a day per stratum: 10 in all, as D6 plans.
    static let cards: [Stratum: Int] = [.founderLong: 3, .memberLong: 3, .founderShort: 2, .memberShort: 2]

    struct Summary {
        /// Uncited lines that hold a fact, from the labels.
        let truth: Int
        let mean: Double
        /// The 5th and 95th percentile of the estimate over the draws.
        let low: Double
        let high: Double
        /// The share of draws whose estimate is zero: no card showed a missed fact.
        let zeroShare: Double
        let cardsPerDraw: Int
    }

    /// The estimate over many draws, each draw covering every day, against the truth. `uncited` holds each day's
    /// uncited lines.
    static func summary(uncited days: [[LineLabel]], draws: Int, seed: UInt64) -> Summary {
        var random = SeededGenerator(seed: seed)
        var estimates: [Double] = []
        var cardsPerDraw = 0
        for _ in 0..<draws {
            var total = 0.0
            cardsPerDraw = 0
            for lines in days {
                let draw = estimate(lines, using: &random)
                total += draw.missed
                cardsPerDraw += draw.cards
            }
            estimates.append(total)
        }
        let sorted = estimates.sorted()
        return Summary(
            truth: days.flatMap { $0 }.filter(\.isFact).count, mean: estimates.reduce(0, +) / Double(max(draws, 1)),
            low: sorted[Int(0.05 * Double(sorted.count))], high: sorted[Int(0.95 * Double(sorted.count))],
            zeroShare: Double(estimates.filter { $0 == 0 }.count) / Double(max(draws, 1)), cardsPerDraw: cardsPerDraw)
    }

    /// One day's draw: the estimated missed fact lines and the cards shown.
    static func estimate(_ uncited: [LineLabel], using random: inout SeededGenerator) -> (missed: Double, cards: Int) {
        let strata = Dictionary(grouping: uncited, by: Stratum.init)
        var missed = 0.0
        var shown = 0
        for stratum in Stratum.allCases {
            let lines = strata[stratum] ?? []
            let drawn = lines.shuffled(using: &random).prefix(min(cards[stratum] ?? 0, lines.count))
            guard !drawn.isEmpty else { continue }
            missed += Double(lines.count) * Double(drawn.filter(\.isFact).count) / Double(drawn.count)
            shown += drawn.count
        }
        return (missed, shown)
    }
}

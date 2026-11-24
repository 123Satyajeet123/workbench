import Foundation
import WorkbenchCore

/// P10: the time of one certificate read when every read replays all runs (Certificate.status today), against a state
/// kept per key that each new run updates once. The kept state holds the wealth, the drift alarm, and a wealth for
/// each rate of a grid, so the bound is read off the grid instead of by 40 replays.
public struct CertificateCost: Sendable {
    public var answersPerRun = 1...3
    public var seed: UInt64 = 20_261_124
    /// The rates the kept state bets against for the bound: 0.1% steps up to the allowed wrong rate.
    public static let boundGrid = (1...100).map { Double($0) / 1_000 }

    public init() {}

    /// The audit answers of `runs` runs at `wrongRate`, each item picked at `RunSettings.standard.pickChance`.
    public func answers(runs: Int, wrongRate: Double) -> [Certificate.Answer] {
        var generator = SeededGenerator(seed: seed)
        return (0..<runs).flatMap { run in
            (0..<Int.random(in: answersPerRun, using: &generator)).map { _ in
                Certificate.Answer(
                    wrong: Double.random(in: 0..<1, using: &generator) < wrongRate,
                    chance: RunSettings.standard.pickChance,
                    run: Int64(run))
            }
        }
    }

    /// The median time of `reads` full reads, and the status the read gave.
    public func replayRead(_ answers: [Certificate.Answer], reads: Int = 5) -> (Duration, Certificate.Status) {
        let certificate = Certificate(answers: answers)
        var status = certificate.status
        let times = (0..<reads).map { _ in ContinuousClock().measure { status = certificate.status } }
        return (times.sorted()[reads / 2], status)
    }

    /// The state kept for one key.
    public struct KeptState {
        var wealth = Certificate.Wealth()
        var alarm = DriftAlarm()
        var grid = CertificateCost.boundGrid.map { Certificate.Wealth(against: $0) }
        var earned = false

        public init() {}

        /// As `Certificate.status`: the run that raises the drift alarm starts a new state and does not count.
        mutating func add(run: [Certificate.Answer]) {
            alarm.add(run: run)
            guard !alarm.isRaised else {
                self = KeptState()
                return
            }
            wealth.add(run: run)
            for index in grid.indices { grid[index].add(run: run) }
            earned = earned || wealth.value >= RunSettings.standard.threshold
        }

        /// As `Certificate.status`: once earned since the last alarm, the least grid rate whose wealth is at its bar.
        var bound: Double? {
            guard earned else { return nil }
            return zip(CertificateCost.boundGrid, grid).first { $0.1.value >= RunSettings.standard.threshold }?.0
                ?? RunSettings.standard.allowedWrong
        }
    }

    /// The mean time to add one run to the kept state and read it, over the last `measured` runs of `answers`.
    public func keptRead(_ answers: [Certificate.Answer], measured: Int = 1_000) -> (Duration, Double?) {
        let runs = Dictionary(grouping: answers) { $0.run ?? 0 }.sorted { $0.key < $1.key }.map(\.value)
        var state = KeptState()
        for run in runs.dropLast(measured) { state.add(run: run) }
        var bound: Double?
        let time = ContinuousClock().measure {
            for run in runs.suffix(measured) {
                state.add(run: run)
                bound = state.bound
            }
        }
        return (time / measured, bound)
    }
}

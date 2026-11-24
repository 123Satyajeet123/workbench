import Foundation
import WorkbenchCore

/// A helper whose wrong rate jumps after it has earned trust. It counts audited runs from the jump to the moment each
/// detector notices: the drift alarm (an e-CUSUM), or the plain certificate whose wealth falls below its bar.
public struct DriftSimulation: Sendable {
    public var trials = 2_000
    public var wrongBefore = 0.05
    public var wrongAfter = 0.25
    public var concentration = 10.0
    public var horizonRuns = 400
    public var delta = RunSettings.standard.delta
    public var seed: UInt64 = 20_261_123

    public init() {}

    public struct Result: Sendable {
        /// Audited runs from the jump to the drift alarm, per trial that earned; nil when it did not fire in time.
        public var alarmRuns: [Int?]
        /// Audited runs from the jump until the plain certificate is no longer earned; nil when it stayed earned.
        public var certificateRuns: [Int?]
        /// Trials that never earned before the jump and so are not in the lists above.
        public var neverEarned: Int
        /// Trials in which the drift alarm fired before the jump, while the rate was still `wrongBefore`.
        public var falseAlarmsBeforeJump: Int
    }

    public func run() -> Result {
        var runs = CorrelatedRuns(concentration: concentration, seed: seed)
        var result = Result(alarmRuns: [], certificateRuns: [], neverEarned: 0, falseAlarmsBeforeJump: 0)
        for _ in 0..<trials {
            var wealth = Certificate.Wealth()
            var alarm = DriftAlarm(delta: delta)
            var raisedBeforeJump = false
            var runsToEarn = 0
            while wealth.value < RunSettings.standard.threshold, runsToEarn < horizonRuns {
                let answers = runs.auditedAnswers(
                    wrongMean: wrongBefore, chance: RunSettings.standard.pickChance, keepRun: true)
                guard !answers.isEmpty else { continue }
                runsToEarn += 1
                wealth.add(run: answers)
                alarm.add(run: answers)
                if alarm.isRaised {
                    raisedBeforeJump = true
                    alarm = DriftAlarm(delta: delta)
                }
            }
            if raisedBeforeJump { result.falseAlarmsBeforeJump += 1 }
            guard wealth.value >= RunSettings.standard.threshold else {
                result.neverEarned += 1
                continue
            }
            var (alarmRuns, certificateRuns): (Int?, Int?) = (nil, nil)
            var audited = 0
            while audited < horizonRuns, alarmRuns == nil || certificateRuns == nil {
                let answers = runs.auditedAnswers(
                    wrongMean: wrongAfter, chance: RunSettings.standard.pickChance, keepRun: true)
                guard !answers.isEmpty else { continue }
                audited += 1
                wealth.add(run: answers)
                alarm.add(run: answers)
                if alarmRuns == nil, alarm.isRaised { alarmRuns = audited }
                if certificateRuns == nil, wealth.value < RunSettings.standard.threshold { certificateRuns = audited }
            }
            result.alarmRuns.append(alarmRuns)
            result.certificateRuns.append(certificateRuns)
        }
        return result
    }

    public struct Stable: Sendable {
        /// The share of trials in which the drift alarm fires within `horizonRuns` audited runs.
        public var alarmed: Double
        /// The share of trials in which the plain certificate, once earned, falls below its bar again.
        public var lostEarned: Double
    }

    /// Both detectors on a wrong rate that never changes: every firing is false.
    public func stable(wrongRate: Double) -> Stable {
        var runs = CorrelatedRuns(concentration: concentration, seed: seed)
        var (alarmed, lostEarned) = (0, 0)
        for _ in 0..<trials {
            var (alarm, wealth) = (DriftAlarm(delta: delta), Certificate.Wealth())
            var (raised, earned, lost) = (false, false, false)
            var audited = 0
            while audited < horizonRuns {
                let answers = runs.auditedAnswers(
                    wrongMean: wrongRate, chance: RunSettings.standard.pickChance, keepRun: true)
                guard !answers.isEmpty else { continue }
                audited += 1
                alarm.add(run: answers)
                wealth.add(run: answers)
                raised = raised || alarm.isRaised
                if wealth.value >= RunSettings.standard.threshold { earned = true } else if earned { lost = true }
            }
            if raised { alarmed += 1 }
            if lost { lostEarned += 1 }
        }
        return Stable(alarmed: Double(alarmed) / Double(trials), lostEarned: Double(lostEarned) / Double(trials))
    }
}

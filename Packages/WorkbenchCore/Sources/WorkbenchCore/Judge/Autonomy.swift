import Foundation

/// What the agent may do for one task type (ADR-020 §4). Each rung asks more of the evidence than the one below.
public enum Rung: String, Codable, CaseIterable, Comparable, Sendable {
    /// The person reads every note. No guarantee; this collects the marks.
    case ask
    /// Notes appear on their own; unverified claims are visibly marked. Stages 0 and 1 are gates.
    case suggest
    /// Verified claims enter the deal's facts without a review step. Wrong claims are at most `RunSettings.standard.allowedWrong`
    /// at the confidence of `RunSettings.standard.confidence`, valid at any time.
    case fill
    /// Notes go to the team. The same bound at the confidence of `RunSettings.standard.shareConfidence`, and the drift alarm quiet.
    case share

    public static func < (lhs: Rung, rhs: Rung) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }

    public var title: String {
        switch self {
        case .ask: "Ask: you read every note"
        case .suggest: "Suggest: unverified claims are marked"
        case .fill: "Fill: verified claims enter the deal"
        case .share: "Share: notes go to the team"
        }
    }
}

/// The rung that the certificate of a task type supports, and the rung in force. The computed rung is shown and never
/// applied by code: the applied rung changes only when the person changes it, and not at all inside a held-out window.
public struct RungReport: Sendable, Equatable {
    public var computed: Rung
    public var applied: Rung
    /// Whether the task's held-out window is open now.
    public var windowIsOpen: Bool
    /// More right runs at the heaviest weight until the next rung's bar, when known.
    public var runsToNext: Int?
    /// The wrong rate the certificate bounds, at the rung's confidence, when earned.
    public var wrongBound: Double?
    public var audited: Int
    /// The applied rung is above what the certificate supports now: the person decides what to do.
    public var exceedsCertificate: Bool { applied > computed }
}

public enum Autonomy {
    /// The rung a certificate supports. `suggest` needs a frozen judge, because it rests on stages 0 and 1 as gates;
    /// `fill` needs the certificate earned at the base confidence; `share` needs it earned at `shareConfidence`.
    public static func computedRung(certificate: Certificate, hasFrozenJudge: Bool) -> Rung {
        if case .earned = certificate.status(at: certificate.settings.shareConfidence) { return .share }
        if case .earned = certificate.status(at: certificate.settings.confidence) { return .fill }
        return hasFrozenJudge ? .suggest : .ask
    }

    public static func report(
        certificate: Certificate, hasFrozenJudge: Bool, applied: Rung, windowIsOpen: Bool
    ) -> RungReport {
        let computed = computedRung(certificate: certificate, hasFrozenJudge: hasFrozenJudge)
        let next = computed == .fill ? certificate.settings.shareConfidence : certificate.settings.confidence
        let status = certificate.status(at: next)
        let earned = certificate.status(at: certificate.settings.confidence)
        var report = RungReport(
            computed: computed, applied: applied, windowIsOpen: windowIsOpen, runsToNext: nil, wrongBound: nil,
            audited: certificate.answers.count)
        if case .needsMore(let runs) = status, computed < .share { report.runsToNext = runs }
        if case .earned(let bound) = earned { report.wrongBound = bound }
        return report
    }
}

/// How well the judge's verdicts agree with the person's marks on the claims it was given a verdict for. Unknown
/// verdicts are not counted: they are coverage, not agreement.
public struct JudgeAgreement: Sendable, Equatable {
    /// The judge said pass and the person said right, or the judge said fail and the person said wrong.
    public var agree = 0
    public var passRight = 0
    public var passWrong = 0
    public var failRight = 0
    public var failWrong = 0
    /// Claims the judge could not decide.
    public var unknown = 0

    public init() {}

    public var marks: Int { agree + passWrong + failRight }
    public var rate: Double? { marks == 0 ? nil : Double(agree) / Double(marks) }

    /// The least agreement the data allow at the 95% level, from the exact binomial bound on disagreement.
    public var lowerBound: Double? {
        marks == 0 ? nil : 1 - ClopperPearson.upperBound(wrong: marks - agree, of: marks, confidence: 0.95)
    }

    /// Cohen's kappa of the judge against the person, over the claims the judge decided.
    public var kappa: Double? {
        guard marks > 0 else { return nil }
        let total = Double(marks)
        let judgePass = Double(passRight + passWrong) / total
        let personRight = Double(passRight + failRight) / total
        let chance = judgePass * personRight + (1 - judgePass) * (1 - personRight)
        guard chance < 1 else { return nil }
        return (Double(agree) / total - chance) / (1 - chance)
    }

    public mutating func add(judge: Verdict, person: Mark) {
        switch (judge, person) {
        case (.pass, .confirmed):
            passRight += 1
            agree += 1
        case (.fail, .rejected):
            failWrong += 1
            agree += 1
        case (.pass, .rejected): passWrong += 1
        case (.fail, .confirmed): failRight += 1
        case (.unknown, _), (_, .proposed): unknown += 1
        }
    }
}

/// Prediction-powered inference lets the judge stand in for part of the person's marks. It is off until the judge's
/// agreement with the person is at least `requiredAgreement` over at least `fewestMarks` dev marks. Nothing switches
/// it on but the numbers.
public enum PredictionPoweredInference {
    public static let requiredAgreement = 0.95
    public static let fewestMarks = 100
    public static let mostMarks = 150

    public static func isOn(_ agreement: JudgeAgreement) -> Bool {
        agreement.marks >= fewestMarks && (agreement.rate ?? 0) >= requiredAgreement
    }
}

extension RungReport {
    /// What the report says in the words a person reads on a page.
    public var plainWords: String {
        var parts = ["In force: \(applied.rawValue).", "\(audited) audited answers."]
        if let wrongBound { parts.append("Wrong claims at most \(Int((wrongBound * 100).rounded()))%.") }
        if let runsToNext { parts.append("At least \(runsToNext) more right runs for the next rung.") }
        if exceedsCertificate { parts.append("The rung in force is above what the marks support.") }
        if windowIsOpen { parts.append("A held-out window is open: the rung does not change.") }
        return parts.joined(separator: " ")
    }
}

extension JudgeAgreement {
    public var plainWords: String {
        guard let rate else {
            return "The judge has no marks of yours to be measured against yet. Prediction-powered inference: off."
        }
        let state = PredictionPoweredInference.isOn(self) ? "on" : "off"
        return
            "The judge agreed with \(Int((rate * 100).rounded()))% of \(marks) of your marks. Prediction-powered inference: \(state), and on only from \(Int(PredictionPoweredInference.requiredAgreement * 100))% over \(PredictionPoweredInference.fewestMarks) marks."
    }
}

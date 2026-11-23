import Foundation

/// One question a team template asks at setup. It is made from a machine's spec field, never written for a template:
/// a machine whose spec has criteria asks for criteria, one with feeds asks for feeds, one with claim types asks for
/// claim types. Machines whose template values for one field are equal share one question.
public struct SetupQuestion: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable {
        case criteria, feeds, claimTypes
    }

    /// The places of the machines among the template's seeds that the answer goes to.
    public let machines: [Int]
    public let machineNames: [String]
    public let kind: Kind
    /// The value the template sets in each of these machines.
    public let templateValue: SetupAnswer

    public var id: String { "\(machines[0]).\(kind.rawValue)" }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// What a person answers to one setup question. It replaces the spec value the template set.
public enum SetupAnswer: Sendable, Equatable {
    case criteria(Criteria)
    case feeds([NewsFeed])
    case claimTypes([ClaimType])
}

public typealias SetupAnswers = [SetupQuestion: SetupAnswer]

extension TeamTemplate {
    /// The questions of the machines' spec fields, in the order of the machines. A machine with the same template
    /// value as an earlier one for a field joins that question.
    public var setupQuestions: [SetupQuestion] {
        var questions: [SetupQuestion] = []
        for (index, seed) in seeds.enumerated() {
            let values: [(SetupQuestion.Kind, SetupAnswer?)] = [
                (.criteria, seed.spec.criteria.map(SetupAnswer.criteria)),
                (.feeds, seed.spec.feeds.map(SetupAnswer.feeds)),
                (.claimTypes, seed.spec.claimTypes.map(SetupAnswer.claimTypes)),
            ]
            for case (let kind, let value?) in values {
                if let shared = questions.firstIndex(where: { $0.kind == kind && $0.templateValue == value }) {
                    let known = questions[shared]
                    questions[shared] = SetupQuestion(
                        machines: known.machines + [index], machineNames: known.machineNames + [seed.name],
                        kind: kind, templateValue: value)
                } else {
                    questions.append(
                        SetupQuestion(machines: [index], machineNames: [seed.name], kind: kind, templateValue: value))
                }
            }
        }
        return questions
    }
}

/// What starting a team made: the machines now in the store, and how many answers went into their specs.
public struct TeamStart: Sendable, Equatable {
    public var machines: [String] = []
    public var answered = 0
}

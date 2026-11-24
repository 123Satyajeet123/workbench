import Foundation
import WorkbenchCore

extension InjectionCorpus {
    /// One planted break for each guard of `problems`, applied to a copy of this corpus. A guard holds in both
    /// directions when the sound corpus has no problem and its planted break adds the problem it names.
    public var plantedBreaks: [(name: String, caught: Bool)] {
        breaks.map { name, expected, plant in
            var copy = self
            guard plant(&copy) else { return (name + " (no case to plant in)", false) }
            return (name, copy.problems.contains { $0.contains(expected) })
        }
    }

    private typealias Plant = (inout InjectionCorpus) -> Bool

    private var breaks: [(String, String, Plant)] {
        [
            (
                "canary removed from its lines", "canary not in its lines",
                plant(where: \.isSecretAttack) { item in
                    let token = item.canary.token
                    item.editLines { $0.text = $0.text.replacingOccurrences(of: token, with: "") }
                }
            ),
            ("canary repeated in two cases", "repeats", Self.repeatCanary),
            ("no exits", "no exits", plant(where: \.isSecretAttack) { $0.exits = [] }),
            (
                "primary exit missing", "miss every primary exit",
                plant(where: \.isMochiAct) { $0.exits = [.answerText] }
            ),
            (
                "real domain", "target not synthetic",
                plant(where: \.isSecretAttack) { $0.inputs[0].lines[0].text += " https://northlake-real.com/x" }
            ),
            (
                "line breaks its grammar", "grammar",
                plant(where: \.isSecretAttack) {
                    $0.inputs[0].lines[0].text = "no number: " + $0.inputs[0].lines[0].text
                }
            ),
            (
                "held-out case edited", "held-out digest",
                plant(where: \.isHeldOut) { $0.expected.outcome += " Edited." }
            ),
            (
                "attack with no attacker line", "attacker line",
                plant(where: \.isAttack) { $0.editLines { $0.attacker = false } }
            ),
            ("hidden with no concealment", "concealment", plant(where: \.isHidden) { $0.concealment = nil }),
            (
                "split counts changed", "split counts",
                { corpus in
                    corpus.manifest.dev += 1
                    return true
                }
            ),
            (
                "secret in an attacker line", "secret canary sits in an attacker line",
                plant(where: \.isSecretAttack) { item in
                    let token = item.canary.token
                    item.editLines { if $0.text.contains(token) { $0.attacker = true } }
                }
            ),
            (
                "exit the task cannot reach", "cannot reach",
                plant(where: \.isDailyRead) { $0.exits.append(.searchQuery) }
            ),
            (
                "task success rests on attacker words", "non-attacker line",
                plant(where: \.keepsFactUnderAttack) { item in
                    let words = item.lines.first(where: \.attacker).map { String($0.text.suffix(12)) } ?? ""
                    item.expected.mustReach = [.init(exit: .factKept, contains: words)]
                }
            ),
            ("multi_source from one input", "multi_source", plant(where: \.isDirect) { $0.technique = .multiSource }),
            (
                "unknown authority", "unknown authority",
                plant(where: \.isAttack) { $0.inputs[0].lines[0].authority = "trusted" }
            ),
            (
                "received fact above group_member", "above group_member",
                plant(where: \.isSharedFact) { $0.inputs[0].lines[0].authority = Authority.ownWords.rawValue }
            ),
        ]
    }

    /// A plant that changes the first case that `matches`; false when no case does.
    private func plant(
        where matches: @escaping (InjectionCase) -> Bool, _ change: @escaping (inout InjectionCase) -> Void
    ) -> Plant {
        { corpus in
            guard let index = corpus.cases.firstIndex(where: matches) else { return false }
            change(&corpus.cases[index])
            return true
        }
    }

    /// Gives the second case the first case's canary, in its lines too.
    private static func repeatCanary(_ corpus: inout InjectionCorpus) -> Bool {
        guard corpus.cases.count > 1 else { return false }
        let (old, token) = (corpus.cases[1].canary.token, corpus.cases[0].canary.token)
        corpus.cases[1].editLines { $0.text = $0.text.replacingOccurrences(of: old, with: token) }
        corpus.cases[1].canary.token = token
        return true
    }
}

extension InjectionCase {
    fileprivate var isAttack: Bool { kind == .attack }
    fileprivate var isSecretAttack: Bool { isAttack && canary.role == .secret }
    fileprivate var isMochiAct: Bool { goal == .act && task.kind == .mochiAsk }
    fileprivate var isHeldOut: Bool { InjectionSplit(caseID: id) == .heldOut }
    fileprivate var isHidden: Bool { technique == .hidden }
    fileprivate var isDailyRead: Bool { task.kind == .dailyRead }
    fileprivate var isDirect: Bool { technique == .direct }
    fileprivate var isSharedFact: Bool { inputs.first?.format == .sharedFact }
    fileprivate var keepsFactUnderAttack: Bool { isAttack && expected.mustReach.contains { $0.exit == .factKept } }

    fileprivate mutating func editLines(_ change: (inout Line) -> Void) {
        for input in inputs.indices {
            for line in inputs[input].lines.indices { change(&inputs[input].lines[line]) }
        }
    }
}

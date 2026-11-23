import WorkbenchCore

/// What a person does with one fact. The key is shown next to the action and runs it in a list.
enum FactAction: Hashable {
    case right, done
    case snooze(days: Int)
    case notRelevant, wrong

    /// The three lengths a snooze offers.
    static let snoozes: [FactAction] = [.snooze(days: 1), .snooze(days: 3), .snooze(days: 7)]

    var key: String {
        switch self {
        case .right: "Y"
        case .done: "D"
        case .snooze: "S"
        case .notRelevant: "X"
        case .wrong: "N"
        }
    }

    var title: String {
        switch self {
        case .right: "Right"
        case .done: "Done"
        case .snooze: "Snooze"
        case .notRelevant: "Not relevant"
        case .wrong: "Wrong"
        }
    }

    var symbol: String {
        switch self {
        case .right: "hand.thumbsup"
        case .done: "checkmark.circle"
        case .snooze: "clock"
        case .notRelevant: "eye.slash"
        case .wrong: "hand.thumbsdown"
        }
    }

    /// The symbol that fills in while a row confirms the action.
    var confirmedSymbol: String {
        switch self {
        case .right: "hand.thumbsup.fill"
        case .done: "checkmark.circle.fill"
        case .snooze: "clock.fill"
        case .notRelevant: "eye.slash.fill"
        case .wrong: "hand.thumbsdown.fill"
        }
    }

    var tone: Tone {
        switch self {
        case .right, .done: .good
        case .snooze: .attention
        case .notRelevant: .neutral
        case .wrong: .bad
        }
    }

    /// What a snooze menu says for this length. Other actions give their title.
    var choiceTitle: String {
        guard case .snooze(let days) = self else { return title }
        switch days {
        case 1: return "1 day"
        case 7: return "A week"
        default: return "\(days) days"
        }
    }

    /// What the toast says after the action.
    func toastText(for title: String) -> String {
        let shortened = title.count > Self.toastTitleLimit ? title.prefix(Self.toastTitleLimit) + "…" : title
        switch self {
        case .right: return "Marked right: \(shortened)"
        case .done: return "Done: \(shortened)"
        case .snooze: return "Snoozed for \(choiceTitle.lowercased()): \(shortened)"
        case .notRelevant: return "Hidden as not relevant: \(shortened)"
        case .wrong: return "Marked wrong: \(shortened)"
        }
    }

    private static let toastTitleLimit = 48
}

extension FactAction {
    /// The actions a fact offers. An audit pick, which the app chose at random, takes right or wrong only. An open fact
    /// of a lifecycle takes done, snooze, not relevant and wrong. Any other unmarked item takes right or wrong. A
    /// marked item takes nothing: its mark is taken back with Undo.
    static func offered(for item: Item, isOpenFact: Bool) -> [FactAction] {
        guard item.state == .proposed else { return [] }
        if item.askedWith != nil { return [.right, .wrong] }
        return isOpenFact ? [.done, .snooze(days: 1), .notRelevant, .wrong] : [.right, .wrong]
    }

    func sameKind(as other: FactAction) -> Bool { key == other.key }
}

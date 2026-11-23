/// What setup did, in words, for the last screen: the machines it makes, the sources turned on and the questions
/// answered or skipped.
struct SetupSummary: Equatable {
    var machines: [String]
    var keepsMachines: Bool
    var asksSources: Bool
    var connected: [String]
    var answered: Int
    var questions: Int

    var lines: [String] {
        var lines = [machinesLine]
        if asksSources { lines.append(sourcesLine) }
        if questions > 0 { lines.append("Questions: \(answered) answered, \(questions - answered) skipped.") }
        return lines
    }

    private var machinesLine: String {
        if keepsMachines { return "This Mac already has machines. Workbench keeps them and adds none." }
        if machines.isEmpty { return "No machines yet. You can add them later." }
        return "Machines to make: \(machines.formatted(.list(type: .and)))."
    }

    private var sourcesLine: String {
        connected.isEmpty ? "No source is turned on yet." : "Sources on: \(connected.formatted(.list(type: .and)))."
    }
}

import Foundation

/// One line of ⌘K: a place to go, a thing to do, or a fact to open.
struct PaletteEntry: Identifiable, Equatable {
    enum Action: Equatable {
        case go(SidebarSelection)
        case pauseCapture, resumeCapture
        case privateMode(on: Bool)
        case chooseCall, stopCall
        case startCall(appID: String?)
        case settings
        case openFact(Int64)
    }

    let id: String
    let title: String
    var detail: String?
    let symbol: String
    var shortcut: String?
    let action: Action
    /// More words a fact is found by, beyond its title.
    var words = ""
}

/// The words a person types into ⌘K, matched against its lines. A place or a thing is found by its name, with the
/// small slips a person makes. A fact is found only by whole words it holds, so a short query does not match half
/// the facts, and at most a few facts show.
enum PaletteSearch {
    static let factLimit = 5
    static let shortestFactQuery = 2

    static func results(for query: String, commands: [PaletteEntry], facts: [PaletteEntry]) -> [PaletteEntry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return commands }
        let found = FuzzySearch.filter(commands, by: query, name: \.title)
        return found + matching(query, in: facts).prefix(factLimit)
    }

    private static func matching(_ query: String, in facts: [PaletteEntry]) -> [PaletteEntry] {
        let typed = words(query)
        guard typed.joined().count >= shortestFactQuery else { return [] }
        return facts.filter { fact in
            let held = words(fact.title + " " + fact.words)
            return typed.allSatisfy { word in held.contains { $0.hasPrefix(word) } }
        }
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}

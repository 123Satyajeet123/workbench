import Foundation

@testable import WorkbenchCore
@testable import WorkbenchUI

/// The sources a blank machine can read, and each one it cannot, with the reason the registry's data gives.
@MainActor
enum Sources {
    static func run() {
        heading("1. The sources the registry offers to a blank machine")
        let offered = Crew.blankMachineSources
        for source in offered {
            print("  offered      \(source.name) (\(source.key)): cites \(source.citation.rawValue)")
        }
        for source in SourceRegistry.all where !offered.contains(source) {
            print("  not offered  \(source.name) (\(source.key)): \(reason(source))")
        }
        check("every offered source gives days of lines", offered.allSatisfy(\.givesDaysOfLines))
        check(
            "a source with its own list or thesis is not offered",
            !offered.contains(.newsArticle) && !offered.contains(.webSearch))
        check(
            "a source with no reader for a machine is not offered",
            !offered.contains(.calendarEvent) && !offered.contains(.callTranscript))
    }

    private static func reason(_ source: SourceDescriptor) -> String {
        source.givesDaysOfLines
            ? "no reader here makes a machine over it yet"
            : "it fetches with a list of companies or a thesis, which a job sentence does not give"
    }
}

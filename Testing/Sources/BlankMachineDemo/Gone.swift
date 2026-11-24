import Foundation

/// The code that replaced a person's machine with a built-in's design is gone, and no code branches on a template id
/// that a blank machine lacks. Two scans of the sources, by pattern.
@MainActor
enum Gone {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func hits(_ pattern: String, in folders: [String], excluding: [String] = []) throws -> [String] {
        let expression = try NSRegularExpression(pattern: pattern)
        var found: [String] = []
        for folder in folders {
            let files = FileManager.default.enumerator(
                at: root.appending(path: folder), includingPropertiesForKeys: nil)
            for case let url as URL in files ?? .init()
            where url.pathExtension == "swift" && !excluding.contains(where: url.path.contains) {
                let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
                for (index, text) in lines.enumerated()
                where expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                    found.append("\(url.lastPathComponent):\(index + 1)  \(text.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        return found
    }

    static func run() throws {
        heading("9. Code that overwrote a machine is gone")
        let sources = ["Packages/WorkbenchCore/Sources/WorkbenchCore", "Packages/WorkbenchUI/Sources/WorkbenchUI"]
        let upgrades = try hits(#"func upgrade\(|update\(toward|store\.upgrade\(|crew\.upgrade\("#, in: sources)
        check(
            "no `upgrade`, `update(toward:)` or caller is left in Core or UI (\(upgrades.count) hits)", upgrades.isEmpty
        )
    }
}

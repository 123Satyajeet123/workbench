import DemoBuild
import Foundation

let usage = "usage: demo-builder <folder> --mails <eml folder> [--dry-run] [--budget <usd>]"
var arguments = Array(CommandLine.arguments.dropFirst())
let dryRun = arguments.contains("--dry-run")
arguments.removeAll { $0 == "--dry-run" }

func take(_ flag: String, from arguments: inout [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

let mails = take("--mails", from: &arguments)
let budget = take("--budget", from: &arguments).flatMap(Double.init) ?? 1.8
guard arguments.count == 1, let mails else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

do {
    let report = try await DemoBuild.run(
        into: URL(filePath: arguments[0]),
        options: BuildOptions(sources: URL(filePath: mails), dryRun: dryRun, budgetUSD: budget),
        progress: { print($0) })
    print(report)
} catch {
    FileHandle.standardError.write(Data("demo-builder: \(error.localizedDescription)\n".utf8))
    exit(1)
}

import Evals
import Foundation
import WorkbenchCore

// Dev only. Probe P-F4: label each line of a dev week that holds a "kal" or "parson" word as past or future.
// Usage: kal-label --store <store folder> --week <first day, yyyy-MM-dd> --chats <id,id> --terms <word,word>
//                  --out <labels file, in worktrace/data/>
// The tool reads a copy of the store and never opens the original. It refuses any week that touches 2026-11-23 to
// 2026-12-06, and it leaves out every day that the repo's hash split holds out. Keys: p past, f future, s skip, q quit.
func option(_ name: String) -> String? {
    CommandLine.arguments.firstIndex(of: name).flatMap { index in
        CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : nil
    }
}

guard let storeFolder = option("--store"), let week = option("--week").flatMap({ WorkDay($0) }),
    let chats = option("--chats"), let terms = option("--terms"), let out = option("--out")
else {
    print(
        "usage: kal-label --store <store folder> --week <yyyy-MM-dd> --chats <id,id> --terms <word,word> --out <file>"
    )
    exit(2)
}
if !FileManager.default.fileExists(atPath: out) {
    FileManager.default.createFile(atPath: out, contents: nil, attributes: [.posixPermissions: 0o600])
}
let file = try FileHandle(forWritingTo: URL(filePath: out))
try file.seekToEnd()
do {
    let labelled = try KalLabelling.run(
        onCopyOf: URL(filePath: storeFolder), chats: chats.split(separator: ",").map(String.init),
        terms: terms.split(separator: ",").map(String.init), weekStarting: week,
        ask: { line, number, total in
            print("\n[\(number)/\(total)] \(line.day)\n\(line.text)\npast (p), future (f), skip (s), quit (q)?")
            while true {
                switch readLine()?.lowercased() {
                case "p": return .label(.past)
                case "f": return .label(.future)
                case "s": return .skip
                case "q", nil: return .quit
                default: print("p, f, s or q")
                }
            }
        },
        record: { try file.write(contentsOf: Data(($0.jsonLine + "\n").utf8)) })
    print("\(labelled) labels written to \(out)")
} catch let refused as HeldOutDays.Refused {
    print("refused: \(refused.day) is held out (2026-11-23 to 2026-12-06). Pick a dev week.")
    exit(1)
}

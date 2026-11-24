import Foundation

@testable import WorkbenchCore

// Plants words in a scratch store through the writers of the app, erases the line that holds one of them through each
// door the app has, and scans every byte of the store folder for the words: UTF-8 and UTF-16, with the store open, after
// a checkpoint, after a new snapshot, and after it is closed. A word that must stay is scanned for too, so a scan that
// finds nothing is shown to be able to find. Prints a line starting LEAK: for each byte of an erased word, FAIL: for
// each promise that did not hold, and ALL OK at the end only when none did. Exits 1 on any.
// Usage: erase-canary

setvbuf(stdout, nil, _IOLBF, 0)
if CommandLine.arguments.dropFirst().first == KilledCall.flag {
    let arguments = CommandLine.arguments
    try await KilledCall.hold(
        in: URL(fileURLWithPath: arguments[2]), program: URL(fileURLWithPath: arguments[3]), prompt: arguments[4])
    exit(0)
}
let findings = Findings()
let root = FileManager.default.temporaryDirectory.appending(path: "erase-canary-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: root) }

if CommandLine.arguments.dropFirst().first == "scale" {
    let lines = CommandLine.arguments.dropFirst(2).first.flatMap(Int.init) ?? 100_000
    try await Scale.run(lines: lines, in: root.appending(path: "scale"), findings: findings)
    exit(findings.isClean ? 0 : 1)
}
if CommandLine.arguments.dropFirst().first == "whatsapp" {
    try await WhatsAppTrial.run(in: root.appending(path: "whatsapp"), findings: findings)
    exit(findings.isClean ? 0 : 1)
}
try SqliteInfo.print(into: findings)
try ScannerSelfTest.run(in: root.appending(path: "self-test"), findings: findings)
try await Control.run(in: root.appending(path: "control"), findings: findings)
try await OldShape.run(in: root.appending(path: "old-shape"), findings: findings)
try await HeldLog.run(in: root.appending(path: "held-log"), findings: findings)
for trigger in Trigger.allCases {
    print("\n== \(trigger.rawValue)")
    try await EraseRun(trigger: trigger, folder: root.appending(path: "\(trigger)"), findings: findings).run()
}

if findings.isClean {
    print("\nALL OK")
} else {
    print("\n\(findings.leaks) leaked copies, \(findings.failures) other failures")
    exit(1)
}

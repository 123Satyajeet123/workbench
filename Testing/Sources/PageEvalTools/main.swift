import Foundation
import PageTools

// The read-only tool server of page-eval, started by the eval only.
// Usage: page-eval-tools <fixture.json> <log.jsonl> <call-cap>
// It reads the fixture, answers JSON-RPC lines on stdin, and appends one line to the log for each tool call.
let arguments = CommandLine.arguments
guard arguments.count == 4, let callCap = Int(arguments[3]),
    let data = FileManager.default.contents(atPath: arguments[1]),
    let fixture = try? JSONDecoder().decode(PageToolFixture.self, from: data)
else {
    FileHandle.standardError.write(Data("usage: page-eval-tools <fixture.json> <log.jsonl> <call-cap>\n".utf8))
    exit(2)
}
FileManager.default.createFile(atPath: arguments[2], contents: nil)
let log = try FileHandle(forWritingTo: URL(filePath: arguments[2]))
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
var service = PageToolService(fixture: fixture, callCap: callCap)
while let line = readLine() {
    let (reply, entry) = service.respond(to: line)
    if let entry { try log.write(contentsOf: encoder.encode(entry) + Data("\n".utf8)) }
    if let reply { print(reply) }
    fflush(stdout)
}

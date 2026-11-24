import Foundation
import GRDB
import Kernel
import Lines
import Synchronization

@testable import WorkbenchCore

// Shows each gate of the LinkedIn export import twice: once where it holds, once where it lets the data through.
// One scratch store, a synthetic CSV, no network. It never opens the live store.
//
//   swift run linkedin-import

struct StubModel: StructuredModel {
    let name = "stub"
    func generate<T: Decodable & Sendable>(_ type: T.Type, schema: JSONSchema, instructions: String, input: String)
        async throws -> ModelAnswer<T>
    {
        let reply = #"{"ok":true}"#
        return ModelAnswer(
            value: try JSONDecoder().decode(T.self, from: Data(reply.utf8)), model: name, usage: Usage(), reply: reply)
    }
}

struct Reply: Decodable, Sendable { let ok: Bool }

nonisolated(unsafe) var failures = 0

func expect(_ claim: String, _ holds: Bool) {
    print("  \(holds ? "yes" : "NO ") \(claim)")
    if !holds { failures += 1 }
}

func oneLine(_ text: String) -> String { text.replacingOccurrences(of: "\n", with: "\\n") }

func heading(_ text: String) { print("\n\(text)") }

let owner = try PersonID("alice")
let stranger = try PersonID("bob")
let moment = Mutex(Date(timeIntervalSince1970: 1_795_000_000))
let directory = FileManager.default.temporaryDirectory.appending(path: "linkedin-import-demo-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: directory) }
let store = try Store(directory: directory, clock: { moment.withLock { $0 } })

func advanceOneDay() { moment.withLock { $0 = $0.addingTimeInterval(86_400) } }

// MARK: Synthetic exports

let notes = """
    Notes:
    "When exporting your connection data, you may notice that some of the email addresses are missing. You will only \
    see email addresses for connections who have allowed their contacts to download or export it."

    """

let firstExport = Data(
    (notes + """
        First Name,Last Name,URL,Company,Position,Connected On
        Ada,Lovelace,https://www.linkedin.com/in/ada-l,"Engines, Analytical",Founder,12 Mar 2023
        Grace,Hopper,https://www.linkedin.com/in/grace-h/,"Navy ""Yard"" Labs","Rear Admiral
        and Compiler Lead",01 Jan 2024
        Quillfeather,Zorbin,https://www.linkedin.com/in/qz,Zorbin Works,Advisor,05 May 2022
        Anonymous,Member,,,,
        """).utf8)

let secondExport = Data(
    (notes + """
        First Name,Last Name,URL,Company,Position,Connected On
        Ada,Lovelace,https://www.linkedin.com/in/ada-l,"Engines, Analytical",Chief Mathematician,12 Mar 2023
        Grace,Hopper,https://www.linkedin.com/in/grace-h/,"Navy ""Yard"" Labs","Rear Admiral
        and Compiler Lead",01 Jan 2024
        Katherine,Johnson,https://www.linkedin.com/in/kj,Orbital Maths,Analyst,02 Feb 2025
        """).utf8)

// MARK: Helpers

func storedLines() throws -> [(url: String, text: String)] {
    try store.writer.read { db in
        try Row.fetchAll(db, sql: "SELECT message_ref, text FROM evidence ORDER BY message_ref")
            .map { (($0["message_ref"] as String?) ?? "", $0["text"] as String) }
    }
}

func copies(of word: String) -> Int {
    let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
    var count = 0
    for case let file as URL in files {
        guard let data = try? Data(contentsOf: file) else { continue }
        var from = data.startIndex
        while let range = data.range(of: Data(word.utf8), in: from..<data.endIndex) {
            count += 1
            from = range.upperBound
        }
    }
    return count
}

func runID() async throws -> RunID {
    try await RecordedModel(StubModel(), store: store).generate(
        Reply.self, schema: .object([.init("ok", .boolean)]), task: "demo", instructions: "demo", input: "demo input",
        holding: [.linkedinExport], window: []
    ).run
}

// MARK: 1. The parse: a preamble, quotes with commas and line breaks, a missing optional column

heading("1. Parse: note lines, quoted commas, quoted line break, no Email Address column")
let parsed = try LinkedInConnections.parse(firstExport)
for connection in parsed.connections { print("  \(connection.profileURL)  <-  \(oneLine(connection.words))") }
expect("three connections read, the row without a URL skipped", parsed.connections.count == 3 && parsed.skipped == 1)
expect("a quoted comma stays in the company", parsed.connections[0].company == "Engines, Analytical")
expect("a quoted line break stays in the position", parsed.connections[1].position == "Rear Admiral\nand Compiler Lead")
expect("doubled quotes become one quote", parsed.connections[1].company == "Navy \"Yard\" Labs")
expect(
    "a trailing slash does not change the key",
    parsed.connections[1].profileURL == "https://www.linkedin.com/in/grace-h")
expect("the missing optional column is nil", parsed.connections.allSatisfy { $0.email == nil })

// MARK: 2. Refusal of a wrong file

heading("2. Refusal: a wrong file changes nothing")
let wrongFiles: [(String, Data)] = [
    ("a sales sheet", Data("Deal,Amount\nAcme,10\n".utf8)),
    ("a connections file without its URL column", Data("First Name,Last Name,Company\nAda,Lovelace,X\n".utf8)),
    ("a header and no rows", Data("First Name,Last Name,URL\n".utf8)),
    ("bytes that are not text", Data([0xFF, 0xFE, 0xC3, 0x28])),
]
for (name, file) in wrongFiles {
    do {
        try store.importLinkedInConnections(file, owner: owner)
        expect("\(name) is refused", false)
    } catch {
        print("  \(name): \(error.localizedDescription)")
        expect("\(name) is refused", error is LinkedInExportError)
    }
}
expect("the store holds no line after the refusals", try storedLines().isEmpty)

// MARK: 3. The first import

heading("3. First import: one line for each connection, named by its profile URL")
let first = try store.importLinkedInConnections(firstExport, owner: owner)
print("  \(first)")
for line in try storedLines() { print("  \(line.url)  \(oneLine(line.text))") }
expect("three lines written, none erased", first.written == 3 && first.erased == 0 && first.skippedRows == 1)
advanceOneDay()
let again = try store.importLinkedInConnections(firstExport, owner: owner)
expect(
    "the same file again writes nothing and erases nothing",
    again.written == 0 && again.unchanged == 3 && again.erased == 0)
expect("the removed-to-be name is in the file now", copies(of: "Quillfeather") > 0)
expect("the old position is in the file now", copies(of: "Founder") > 0)

// MARK: 4. A newer export

heading("4. Newer export: Ada changed, Quillfeather removed, Katherine added")
advanceOneDay()
let second = try store.importLinkedInConnections(secondExport, owner: owner)
print("  \(second)")
for line in try storedLines() { print("  \(oneLine(line.text))") }
expect("two lines written (Ada changed, Katherine new), one unchanged", second.written == 2 && second.unchanged == 1)
expect("two lines erased (Ada's old line, Quillfeather)", second.erased == 2)
expect("three lines stay: none of the removed connection", try storedLines().count == 3)
expect("Ada's new position is stored", try storedLines().contains { $0.text.contains("Chief Mathematician") })
expect("Quillfeather is in no byte of the file, its log or any backup", copies(of: "Quillfeather") == 0)
expect("Ada's old position is in no byte either", copies(of: "Founder") == 0)
expect("an unchanged connection kept its line", copies(of: "Compiler Lead") > 0)

// MARK: 5. The label

heading("5. Label: the importer's own, read only by the owner")
let ownerAudience = try ReaderAudience(reader: owner)
let strangerAudience = try ReaderAudience(reader: stranger)
let stored = try store.queries.currentLines(
    in: ["connections"], from: .distantPast, to: .distantFuture)
expect("the lines are found by their container", stored.count == 3)
expect("the owner is admitted to every line", stored.allSatisfy { ownerAudience.admits($0) })
expect("another reader is admitted to none", stored.allSatisfy { !strangerAudience.admits($0) })
let source = try SourceDescriptor.linkedinExport.sourceID(owner: owner)
expect(
    "the label is the label of the importer's own source",
    stored.allSatisfy { $0.provenance?.label == Label(source: source) })

// MARK: 6. Search

heading("6. searchLines: the owner finds a connection, another reader does not")
let found = try store.searchLines("Katherine", in: ToolContext(run: try await runID(), reader: owner))
let hidden = try store.searchLines("Katherine", in: ToolContext(run: try await runID(), reader: stranger))
expect("the owner finds Katherine", found.count == 1 && found[0].text.contains("Orbital Maths"))
expect("another reader finds nothing", hidden.isEmpty)
let gone = try store.searchLines("Quillfeather", in: ToolContext(run: try await runID(), reader: owner))
expect("the owner does not find the removed connection", gone.isEmpty)

print(failures == 0 ? "\nAll gates hold." : "\n\(failures) gate(s) failed.")
exit(failures == 0 ? 0 : 1)

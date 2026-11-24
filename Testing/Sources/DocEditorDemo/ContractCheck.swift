import EditorHarness
import Foundation

@testable import WorkbenchUI

/// One message of every kind the bridge has, with fixed words. Swift writes them to `contract/samples.json`; the node
/// check of the editor validates the same file against the schema, so both sides keep to one contract.
enum ContractSamples {
    static let toSwift: [String: EditorMessage] = [
        "ready": .ready(contract: 1),
        "ops": .ops(
            seq: 3,
            ops: [
                .insert(id: "n1", after: nil, text: "# A heading"), .insert(id: "n2", after: "n1", text: "Words"),
                .update(id: "n2", text: "Words, *marked*"), .move(id: "n2", after: nil), .delete(id: "n3"),
                .merge(id: "n4", into: "n2"), .mark(fact: 12, .wrong),
                .view(block: "m1", form: "board", groupBy: "project"), .mark(fact: 12, .done),
                .field(id: "document.title", text: "Pip Example"), .heading(block: "m1", text: "By project"),
                .setting(key: "watch.from", value: "8"), .ask(text: "add a table of promises"),
            ]),
        "openCite": .open(.cite(ref: "fact:12")),
        "openLink": .open(.link(url: "https://example.com/a")),
        "openPicker": .open(.picker(source: "whatsapp_chats")),
        "openAction": .open(.action(.read)),
        "blocked": .blocked(directive: "img-src", uri: "https://example.com/x.png"),
        "idle": .idle,
        "layout": .layout(height: 640, caret: CaretBox(top: 120, bottom: 144)),
        "layoutWithoutCaret": .layout(height: 640, caret: nil),
    ]

    static let toEditor: [String: HostMessage] = [
        "environment": .environment(
            EditorEnvironment(
                appearance: .dark, reduceMotion: true, editable: false, tokens: ["page": "rgba(25, 25, 25, 1.000)"])),
        "load": .load(
            [
                .field(id: "document.title", look: .title, hint: "Name this machine.", text: "Pip Example"),
                .note(id: "n1", text: "Plain words"),
            ]
                + views.enumerated().map { .machine(id: "m\($0.offset)", view: $0.element, standing: .live) }
                + [.machine(id: "m10", view: .heading(text: "Proposed"), standing: .added)]),
        "apply": .apply([
            .insert(after: nil, block: .machine(id: "m9", view: .heading(text: "New"), standing: .replacement)),
            .insert(after: "n1", block: .note(id: "n5", text: "- item")),
            .update(
                block: .machine(
                    id: "m9", view: .erased(note: "The message this came from was deleted"), standing: .removed)),
            .move(id: "n5", after: "m9"), .remove(id: "n5"),
        ]),
        "ack": .ack(seq: 3, renames: [BlockRename(from: "n2", to: "n6")]),
        "flush": .flush,
    ]

    static let views: [MachineView] = [
        .heading(text: "Open follow-ups"),
        .text(
            text: "Asha waits for the deck.",
            cites: [
                CiteChip(ref: "fact:12", label: "Asha: the deck", opens: true),
                CiteChip(ref: "request", label: "Your request", opens: false),
            ]),
        .facts(
            FactsRendering(
                title: "Open follow-ups", layout: "list", countText: "1 fact", needsText: "1 needs you", limit: 0,
                viewBar: FactsRendering.ViewBar(
                    form: "foldedList", forms: ["foldedList", "list", "table"], groupBy: "person",
                    groups: ["person", "kind"]),
                columns: ["quote", "kind"], tallyColumns: ["ask"],
                sections: [
                    FactsRendering.Section(
                        name: "Asha Example", countText: "1 fact", count: 1, needs: 1,
                        summary: FactsRendering.Summary(
                            text: "Asha Example waits for the deck.",
                            cites: [CiteChip(ref: "fact:12", label: "send the deck", opens: true)]),
                        tally: [FactsRendering.Tally(value: "ask", count: 1, tone: "attention")],
                        latest: "send the deck", latestDay: "Tue 25 Nov",
                        rows: [
                            FactsRendering.Row(
                                fact: 12, subject: "", words: "\u{201C}send the deck\u{201D}",
                                cells: ["\u{201C}send the deck\u{201D}", "ask"],
                                needs: [FactsRendering.Tag(text: "Late 2 days", tone: "bad")],
                                tags: [FactsRendering.Tag(text: "ask", tone: "attention")], due: "Due Sun 23 Nov",
                                state: "", marks: [.right, .wrong, .done])
                        ])
                ])),
        .grid(
            GridRendering(
                title: "What was promised", columns: ["Item", "Amount", "Count", "Check"],
                rows: [
                    [
                        GridRendering.Cell(text: "The deck", kind: "words", source: "The deck"),
                        GridRendering.Cell(text: "120", kind: "formula", source: "=SUM(B1:B2)"),
                        GridRendering.Cell(text: "80", kind: "number", source: "80"),
                        GridRendering.Cell(text: "Cannot work this out", kind: "failed", source: "=A1/0"),
                    ]
                ],
                cites: [])),
        .picker(PickerRendering(source: "whatsapp_chats", title: "WhatsApp chats to read", note: "", available: true)),
        .status(
            StatusRendering(
                notices: ["This page is read-only."],
                sentence: "Reads every hour.", journal: ["Read 3 parts.", "Kept 2 facts."],
                act: ActionLink(name: .read, label: "Read now"))),
        .settings(
            SettingsRendering(sentences: [
                SettingsRendering.Sentence(
                    parts: [
                        .words("Reads every "), .chip("watch.every", text: "60", entry: .number), .words(" minutes: "),
                        .chip("watch.on", text: "on", entry: .choice, choices: ["on", "off"]),
                        .chip("nudge.time", text: "8 PM", entry: .time),
                    ], note: "Changed from 9 to 8.", act: ActionLink(name: .undo, label: "Undo"))
            ])),
        .line(LineRendering(text: "More is kept apart.", act: ActionLink(name: .more, label: "Open it"))),
        .erased(note: "The message this came from was deleted"),
    ]

    /// The samples as the snapshot file holds them: sorted keys, two spaces.
    static func snapshot() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let both = ["toEditor": try object(toEditor), "toSwift": try object(toSwift)]
        let data = try JSONSerialization.data(
            withJSONObject: both, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self) + "\n"

        func object<T: Encodable>(_ messages: [String: T]) throws -> [String: Any] {
            try messages.mapValues { try JSONSerialization.jsonObject(with: try encoder.encode($0)) }
        }
    }
}

/// Checks that Swift and the editor keep to one contract: the snapshot of Swift's samples is the committed file; the
/// samples decode back to the same values; and the schema names exactly the kinds of message the samples have.
struct ContractCheck {
    static let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(
        path: "../../../Packages/WorkbenchUI/Editor/contract"
    ).standardized
    static let discriminators = ["type", "op", "change", "kind"]

    func run(update: Bool) throws -> [String] {
        let snapshotFile = Self.folder.appending(path: "samples.json")
        let snapshot = try ContractSamples.snapshot()
        if update { try snapshot.write(to: snapshotFile, atomically: true, encoding: .utf8) }
        var report: [String] = []
        let committed = try String(contentsOf: snapshotFile, encoding: .utf8)
        guard committed == snapshot else { throw DemoFailure("samples.json is not what Swift writes") }
        report.append("samples.json equals Swift's encoding (\(snapshot.utf8.count) bytes)")
        try roundTrip()
        report.append("every sample decodes back to the same value")
        let schemaKinds = try kinds(inSchema: try Data(contentsOf: Self.folder.appending(path: "bridge.schema.json")))
        let sampleKinds = try kinds(inSamples: Data(snapshot.utf8))
        guard schemaKinds == sampleKinds else {
            throw DemoFailure(
                "schema and samples differ: only in schema \(schemaKinds.subtracting(sampleKinds).sorted()), only in samples \(sampleKinds.subtracting(schemaKinds).sorted())"
            )
        }
        report.append("schema and samples name the same \(schemaKinds.count) kinds of message, op, change and block")
        return report
    }

    private func roundTrip() throws {
        let encoder = EditorHost.encoder
        for (name, message) in ContractSamples.toSwift {
            guard try JSONDecoder().decode(EditorMessage.self, from: try encoder.encode(message)) == message else {
                throw DemoFailure("\(name) does not decode to itself")
            }
        }
        for (name, message) in ContractSamples.toEditor {
            guard try JSONDecoder().decode(HostMessage.self, from: try encoder.encode(message)) == message else {
                throw DemoFailure("\(name) does not decode to itself")
            }
        }
    }

    /// Every `const` or `enum` value that a schema definition gives a discriminating property, as `key=value`.
    private func kinds(inSchema data: Data) throws -> Set<String> {
        var found: Set<String> = []
        func walk(_ node: Any) {
            if let object = node as? [String: Any] {
                if let properties = object["properties"] as? [String: Any] {
                    for key in Self.discriminators {
                        guard let property = properties[key] as? [String: Any] else { continue }
                        let values =
                            (property["const"] as? String).map { [$0] } ?? (property["enum"] as? [String]) ?? []
                        for value in values { found.insert("\(key)=\(value)") }
                    }
                }
                object.values.forEach(walk)
            } else if let list = node as? [Any] {
                list.forEach(walk)
            }
        }
        walk(try JSONSerialization.jsonObject(with: data))
        return found
    }

    /// Every discriminating value the samples use, as `key=value`.
    private func kinds(inSamples data: Data) throws -> Set<String> {
        var found: Set<String> = []
        func walk(_ node: Any) {
            if let object = node as? [String: Any] {
                for key in Self.discriminators {
                    if let value = object[key] as? String { found.insert("\(key)=\(value)") }
                }
                object.values.forEach(walk)
            } else if let list = node as? [Any] {
                list.forEach(walk)
            }
        }
        walk(try JSONSerialization.jsonObject(with: data))
        return found
    }
}

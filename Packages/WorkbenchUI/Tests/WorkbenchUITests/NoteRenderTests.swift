import AppKit
import Foundation
import Kernel
import SwiftUI
import Testing
import WorkbenchCore

@testable import WorkbenchUI

/// The note editor and the add-fact sheet drawn to PNG files, in light and dark. The folder comes from `NOTE_SHOTS_DIR`,
/// else the temporary folder.
@MainActor
@Suite struct NoteRenderTests {
    private static let owner = try! PersonID("owner-1")

    private func notes(_ texts: [String], project: String = "Bolt Pay") async throws -> ProjectNotes {
        let store = try scratchStore()
        let notes = ProjectNotes(store: store, owner: Self.owner)
        guard !texts.isEmpty else { return notes }
        var document = NoteDocument(note: try #require(NoteID(project: project)))
        document.replace(0..<0, with: texts.joined(separator: "\n"))
        _ = try await store.saveNote(try #require(document.pendingChange()), owner: Self.owner)
        return notes
    }

    private func shoot(_ view: some View, named name: String, width: CGFloat, dark: Bool) throws {
        let framed = view.padding(Space.xl).frame(width: width, alignment: .topLeading)
            .background(Color.pageFill).environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingView(rootView: framed)
        host.frame = CGRect(origin: .zero, size: CGSize(width: width, height: 10))
        let window = NSWindow(contentRect: host.frame, styleMask: [], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.frame.size.height = host.fittingSize.height
        window.setContentSize(host.frame.size)
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let folder =
            ProcessInfo.processInfo.environment["NOTE_SHOTS_DIR"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = bitmap.representation(using: .png, properties: [:]) ?? Data()
        guard png.count > 4_000 else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: folder.appending(path: "\(name)-\(dark ? "dark" : "light").png"))
    }

    private static let written = [
        "Bolt Pay wants a pilot with three branches by January. Meera is the contact; she asked for the security answers first.",
        "Their stack is mostly Postgres on AWS. Ask Rahul whether the connector is ready.",
        "नमस्ते टीम, पायलट के लिए कल तक डेक भेजना है 👍",
    ]

    @Test(arguments: [false, true]) func theNoteWithWords(dark: Bool) async throws {
        let notes = try await notes(Self.written)
        try shoot(
            ProjectNotesView(project: "Bolt Pay").environment(notes), named: "notes-written", width: 620, dark: dark)
    }

    @Test(arguments: [false, true]) func anEmptyNoteShowsOnlyAQuietLine(dark: Bool) async throws {
        let notes = try await notes([])
        try shoot(
            ProjectNotesView(project: "Bolt Pay").environment(notes), named: "notes-empty", width: 620, dark: dark)
    }

    @Test(arguments: [false, true]) func theAddFactSheet(dark: Bool) throws {
        let sheet = AddFactModel(spec: .team, people: ["Asha", "Meera"], project: "Bolt Pay") { _ in }
        sheet.words = "Send Meera the security answers"
        sheet.kind = "commitment"
        sheet.person = "Rahul"
        sheet.due = .tomorrow
        try shoot(AddFactSheet(model: sheet, close: {}), named: "add-fact", width: 560, dark: dark)
    }

    @Test(arguments: [false, true]) func theEmptyAddFactSheet(dark: Bool) throws {
        let sheet = AddFactModel(spec: .team, project: "Bolt Pay") { _ in }
        try shoot(AddFactSheet(model: sheet, close: {}), named: "add-fact-empty", width: 560, dark: dark)
    }
}

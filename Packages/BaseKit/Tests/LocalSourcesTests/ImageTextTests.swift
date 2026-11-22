import AppKit
import Foundation
import Testing
import WorkbenchCore

@testable import LocalSources

/// A PNG with `text` drawn large, black on white.
func writeTextImage(_ text: String, to url: URL) throws {
    let image = NSImage(size: NSSize(width: 900, height: 160))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 900, height: 160).fill()
    (text as NSString).draw(
        at: NSPoint(x: 30, y: 55),
        withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black])
    image.unlockFocus()
    let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
}

/// A photo sent to a group is read as the text in it, on this Mac, then its caption.
@Suite struct ImageTextTests {
    private func photoLines(
        path: String, caption: String?, at now: Date = WhatsAppEvidenceTests.now, prepare: (WhatsAppFixture) throws -> Void
    ) async throws -> [String] {
        let rig = try WhatsAppEvidenceTests.Rig()
        try prepare(rig.fixture)
        try rig.fixture.message(chat: 4, type: 1, text: nil, mediaPath: path, title: caption, member: 1, pk: 11)
        rig.move(to: now)
        try await rig.ingest()
        return try rig.texts()
    }

    @Test func aGroupPhotoReadsAsTheTextInItThenItsCaption() async throws {
        let lines = try await photoLines(path: "Media/shot.jpg", caption: "build 4") {
            try writeTextImage("OTA done", to: $0.container.appending(path: "Message/Media/shot.jpg"))
        }
        let line = try #require(lines.first)
        #expect(lines.count == 1 && line.hasPrefix("[photo] ") && line.contains("OTA done") && line.hasSuffix("— build 4"))
    }

    @Test func aPhotoOutsideTheMessageFolderIsNotRead() async throws {
        let lines = try await photoLines(path: "../outside.png", caption: "caption only") {
            try writeTextImage("SECRET", to: $0.container.appending(path: "outside.png"))
        }
        #expect(lines == ["caption only"])
    }

    @Test func aPhotoOlderThanTheRetentionIsNotRead() async throws {
        let later = WhatsAppEvidenceTests.now.addingTimeInterval(CapturePolicy.retention + 3600)
        let lines = try await photoLines(path: "Media/shot.jpg", caption: "old one", at: later) {
            try writeTextImage("OTA done", to: $0.container.appending(path: "Message/Media/shot.jpg"))
        }
        #expect(lines == ["old one"], "the first reading of a long chat does not recognize every photo it held")
    }
}

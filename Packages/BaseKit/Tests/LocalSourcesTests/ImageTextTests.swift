import AppKit
import Foundation
import Testing

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

@Suite struct ImageTextTests {
    @Test func theTextInAScreenshotIsReadOnThisMac() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "img-\(UUID().uuidString)/shot.png")
        try writeTextImage("Build 4.1.11 passed", to: file)
        #expect(ImageText.recognize(file).contains("Build 4.1.11 passed"))
        let notImage = file.deletingLastPathComponent().appending(path: "note.png")
        try Data("not an image".utf8).write(to: notImage)
        #expect(ImageText.recognize(notImage).isEmpty)
    }

    @Test func aGroupPhotoComesWithItsFile() async throws {
        let fixture = try WhatsAppFixture()
        try writeTextImage("OTA done", to: fixture.container.appending(path: "Message/Media/shot.jpg"))
        try fixture.message(chat: 4, type: 1, text: nil, mediaPath: "Media/shot.jpg", member: 1)
        let entry = try #require(
            try await WhatsAppChatReader(container: fixture.container, chatJID: groupJID, policy: whatsappOn).entries()
                .first)
        #expect(entry.kind == .photo)
        guard case .file(let url) = entry.media else {
            Issue.record("the photo's file is inside the Message folder")
            return
        }
        #expect(ImageText.recognize(url).contains("OTA done"))
    }
}

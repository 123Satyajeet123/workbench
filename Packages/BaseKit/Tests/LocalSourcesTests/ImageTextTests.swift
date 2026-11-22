import AppKit
import Foundation
import Testing
import WorkbenchCore

@testable import LocalSources

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

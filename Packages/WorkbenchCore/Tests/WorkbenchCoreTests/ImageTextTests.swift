import Foundation
import Synchronization
import Testing

@testable import WorkbenchCore

@Suite struct ImageTextTests {
    @Test func aFileThatIsNotAnImageHoldsNoText() throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notImage = folder.appending(path: "note.png")
        try Data("not an image".utf8).write(to: notImage)
        #expect(ImageText.recognize(notImage).isEmpty)
    }

    @Test func aPhotoIsRecognizedOnceUntilItsFileChangesAndTheMemoForgetsTheOldest() throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let calls = Mutex(0)
        let memo = ImageText.Memo(capacity: 2) { url in
            calls.withLock { $0 += 1 }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        let first = folder.appending(path: "a.png")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        #expect(memo.text(in: first) == "one" && memo.text(in: first) == "one")
        #expect(calls.withLock { $0 } == 1, "the second reading reuses the text")

        try "changed".write(to: first, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: first.path)
        #expect(memo.text(in: first) == "changed", "a changed file is read again")
        #expect(calls.withLock { $0 } == 2)

        for name in ["b.png", "c.png"] {
            try name.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
            _ = memo.text(in: folder.appending(path: name))
        }
        _ = memo.text(in: first)
        #expect(calls.withLock { $0 } == 5, "past its capacity the oldest text is forgotten")
    }

    @MainActor @Test func photosAreReadOffTheMainThreadEvenWhenTheWindowAsks() async throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = folder.appending(path: "a.png")
        try "one".write(to: photo, atomically: true, encoding: .utf8)
        let onMain = Mutex(false)
        let memo = ImageText.Memo { url in
            onMain.withLock { $0 = $0 || Thread.isMainThread }
            return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        #expect(await memo.texts(in: [photo]) == [photo: "one"])
        #expect(!onMain.withLock { $0 })
    }
}

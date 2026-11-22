import Foundation
import Testing

@testable import WorkbenchCore

/// The store has one writer process: the one that holds the lock on its folder.
@Suite struct StoreLockTests {
    /// What another process finds when it tries the same lock: `got` or `busy`.
    private func otherProcessTries(_ folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/perl")
        process.arguments = [
            "-MFcntl=:flock", "-e",
            #"open(F, ">>", $ARGV[0]) or die; print flock(F, LOCK_EX | LOCK_NB) ? "got" : "busy""#,
            folder.appending(path: StoreLock.fileName).path,
        ]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return text
    }

    @Test func aSecondLockOnTheSameFolderFailsWhileTheFirstIsHeldAndWorksAfterItIsReleased() throws {
        let folder = temporaryDirectory()
        var first: StoreLock? = try StoreLock(directory: folder)
        let path = folder.appending(path: StoreLock.fileName).path
        #expect(throws: StoreLock.Failure.alreadyOpen(path)) { try StoreLock(directory: folder) }
        first = nil
        _ = first
        _ = try StoreLock(directory: folder)
    }

    @Test func anotherFolderHasItsOwnLock() throws {
        let one = try StoreLock(directory: temporaryDirectory())
        let two = try StoreLock(directory: temporaryDirectory())
        _ = (one, two)
    }

    @Test func anotherProcessSeesTheLockWhileItIsHeldAndNotAfter() throws {
        let folder = temporaryDirectory()
        var lock: StoreLock? = try StoreLock(directory: folder)
        #expect(try otherProcessTries(folder) == "busy")
        lock = nil
        _ = lock
        #expect(try otherProcessTries(folder) == "got")
    }

    @Test func theHostCodeHoldsNoLock() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources").standardized
        for target in ["WorkbenchPages", "PagesRelay"] {
            let folder = sources.appending(path: target)
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                let text = try String(contentsOf: file, encoding: .utf8)
                #expect(!text.contains("flock") && !text.contains("StoreLock"), "\(file.lastPathComponent)")
            }
        }
    }
}

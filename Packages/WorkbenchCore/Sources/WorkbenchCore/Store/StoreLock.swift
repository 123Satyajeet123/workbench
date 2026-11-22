import Darwin
import Foundation

/// The right to open the store for writing. One process holds it for its whole life; the kernel frees it when that
/// process ends, even by a crash. A second app copy cannot take it, so it never opens the store: the store has one
/// writer process. The native host never asks for it.
public final class StoreLock: Sendable {
    public enum Failure: Error, Equatable {
        case alreadyOpen(String)
        case cannotLock(String, Int32)
    }

    public static let fileName = "writer.lock"

    private let descriptor: Int32

    /// Takes the lock for the store folder, or throws `alreadyOpen` when another process holds it.
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: Self.fileName).path
        let file = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw Failure.cannotLock(path, errno) }
        guard flock(file, LOCK_EX | LOCK_NB) == 0 else {
            let reason = errno
            close(file)
            throw reason == EWOULDBLOCK ? Failure.alreadyOpen(path) : Failure.cannotLock(path, reason)
        }
        descriptor = file
    }

    deinit { close(descriptor) }
}

extension StoreLock.Failure: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyOpen: "Workbench is already open. Only one copy can keep your data."
        case .cannotLock: "Workbench could not lock its data folder."
        }
    }
}

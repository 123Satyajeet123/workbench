import Foundation

@testable import WorkbenchCore

func makeStore() throws -> Store {
    try Store(directory: FileManager.default.temporaryDirectory.appending(path: "evals-\(UUID().uuidString)"))
}

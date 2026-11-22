import Foundation
import GRDB

public enum SchemaError: Error, Equatable, LocalizedError {
    case newerVersion

    public var errorDescription: String? { "This store was made by a newer Workbench. Install the newer version." }
}

enum StoreDatabase {
    static func open(at url: URL, busyTimeout: TimeInterval) throws -> DatabasePool {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var opened: Result<DatabasePool, any Error>?
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { url in
            opened = Result { try openPool(at: url.path, busyTimeout: busyTimeout) }
        }
        if let coordinationError { throw coordinationError }
        return try opened!.get()
    }

    private static func openPool(at path: String, busyTimeout: TimeInterval) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(busyTimeout)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete=ON")
            guard try Int.fetchOne(db, sql: "PRAGMA secure_delete") == 1 else {
                throw StoreError.settingNotApplied("secure_delete")
            }
        }
        return try DatabasePool(path: path, configuration: configuration)
    }
}

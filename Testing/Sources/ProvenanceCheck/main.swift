import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
defer { try? FileManager.default.removeItem(at: scratch) }

try runRegistryChecks()
try runEraseChecks(closureOnly: false)
try runEraseChecks(closureOnly: true)
try runOldAgainstNewChecks()
try runBackfillChecks()
try runRevokeChecks(closureOnly: false)
try runRevokeChecks(closureOnly: true)
try runMarkerChecks()
try runSnapshotChecks()

if failures.isEmpty {
    print("ALL OK")
} else {
    for failure in failures { print("FAILED: \(failure)") }
    exit(1)
}

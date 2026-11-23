import Foundation

// Proves the machine page store on a new, empty store in a temporary folder, with synthetic data and no model call.
// Usage: swift run MachinePageDemo
do {
    try await MachinePageDemo.run()
    print("ALL OK")
} catch {
    print("FAILED: \(error)")
    exit(1)
}

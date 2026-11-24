import Foundation

/// What the demo found. A line that starts with `LEAK:` is a byte or a row of an erased word that is still there; a line
/// that starts with `FAIL:` is another promise that did not hold, or a scan that cannot be trusted.
final class Findings {
    private(set) var leaks = 0
    private(set) var failures = 0

    func leak(_ line: String) {
        leaks += 1
        print("LEAK: \(line)")
    }

    func fail(_ line: String) {
        failures += 1
        print("FAIL: \(line)")
    }

    func ok(_ line: String) { print("ok   \(line)") }

    func expect(_ holds: Bool, _ line: String) { holds ? ok(line) : fail(line) }

    var isClean: Bool { leaks == 0 && failures == 0 }
}

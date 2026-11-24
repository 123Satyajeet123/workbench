import EditorHarness

/// Every claim of the demo prints once, and the count of failed claims decides the last line.
@MainActor var failures: [String] = []

@MainActor
func check(_ claim: String, _ holds: Bool) {
    print("  \(holds ? "yes" : "NO ")  \(claim)")
    if !holds { failures.append(claim) }
}

func heading(_ text: String) { print("\n\(text)") }

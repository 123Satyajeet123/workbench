import Testing

/// Runs a property on a deliberately wrong implementation and passes only if the property fails on it.
/// Swift Testing records an issue when the body records none, so a property that cannot see its break turns red.
func expectPlantedBreakCaught(_ name: String, _ property: () async -> Void) async {
    await withKnownIssue("planted break: \(name)") {
        await property()
    }
}

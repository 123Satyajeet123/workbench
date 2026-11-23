import WorkbenchCore

/// The menu bar icon's look. A recording comes first, so consent is always visible; then something that needs the
/// person; then whether capture runs.
enum MenuBarGlyph: Hashable {
    case off, capturing, recording, needsYou

    init(isRecording: Bool, needs: Int, status: CaptureStatus) {
        self =
            if isRecording {
                .recording
            } else if needs > 0 {
                .needsYou
            } else if status == .capturing {
                .capturing
            } else {
                .off
            }
    }
}

enum MenuBarStatus {
    /// The first line of the menu: "Capture on · Pip reading".
    static func line(capture: CaptureStatus, reading: [String]) -> String {
        let capture = "Capture \(capture.title.lowercased())"
        guard let who = IslandState.readingLabel(of: reading) else { return capture }
        return "\(capture) · \(who) reading"
    }
}

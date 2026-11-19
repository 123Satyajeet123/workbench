import SwiftUI
import WorkbenchCore

/// The read button, the view picker and what the day's source holds, with the switches the source needs.
struct ReadControls: View {
    let model: HelperModel
    @Environment(ModelSettings.self) private var models
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Button("Read this day") { Task { await model.read() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.phase == .reading || hasNothingToRead || model.isPaused)
                ReadPhaseLabel(
                    phase: model.phase, items: model.spec.itemsNoun, droppedBecause: "not backed by the source")
                Spacer()
                ViewPicker(model: model)
            }
            Text(note).textStyle(.callout).foregroundStyle(.supporting)
            if model.source is ScreenSource, !capture.isOn(.screen) {
                Button("Turn on Screen") { capture.set(.screen, on: true) }
                    .help("Workbench keeps which app, window and page you are in. Never pixels or keystrokes.")
            }
            if let source = model.source as? PageSource {
                HStack {
                    if !capture.isOn(.screenText) {
                        Button("Turn on Screen text") { capture.set(.screenText, on: true) }
                    }
                    Button("Change sites") { model.attempt("clear the sites") { try source.choose("") } }
                }
            }
        }
    }

    /// A screen or page machine has nothing to read on a day without activity; a chat machine always may try.
    private var hasNothingToRead: Bool {
        if let screen = model.source as? ScreenSource { return screen.sessions.isEmpty }
        if let pages = model.source as? PageSource { return pages.pageReading.pages.isEmpty }
        return false
    }

    private var note: String {
        if let screen = model.source as? ScreenSource { return screenNote(screen) }
        if let pages = model.source as? PageSource { return pageNote(pages) }
        return
            "Reading sends this day's messages, and the text in its photos (read on this Mac), to \(models.choice.title). Each call is on the Runs page."
    }

    private func pageNote(_ source: PageSource) -> String {
        let reading = source.pageReading
        guard !reading.pages.isEmpty else {
            return
                "No page text from these sites on this day. Pages come from the Workbench browser extension while Screen text is on."
        }
        let left =
            reading.leftOut == 0 ? "" : " \(reading.leftOut) later pages are past the size limit and are left out."
        return "\(reading.pages.count) page views. Reading sends their text to \(models.choice.title).\(left)"
    }

    private func screenNote(_ source: ScreenSource) -> String {
        guard !source.sessions.isEmpty else {
            return capture.isOn(.screen)
                ? "Screen is on. The timeline fills as you work; read the day later."
                : "Screen is off, so there is no timeline yet. Turning it on keeps which app, window and page you are in; never pixels or keystrokes."
        }
        let minutes = source.sessions.reduce(0) { $0 + $1.minutes }
        return
            "\(source.sessions.count) windows, \(minutes / 60) h \(minutes % 60) min on screen. Reading sends their titles and addresses to \(models.choice.title); never the text on screen."
    }
}

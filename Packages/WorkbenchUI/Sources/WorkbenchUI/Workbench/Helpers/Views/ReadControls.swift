import SwiftUI
import WorkbenchCore

/// One small line above a machine's items: the read button, what the last reading did, and the view picker.
struct ReadBar: View {
    let model: HelperModel

    var body: some View {
        HStack(spacing: Space.m) {
            Button("Read now") { Task { await model.read() } }
                .disabled(model.phase == .reading || hasNothingToRead || model.isPaused)
            ReadPhaseLabel(phase: model.phase, items: model.spec.itemsNoun, droppedBecause: "not backed by the source")
            Spacer()
            ViewPicker(model: model)
        }
    }

    /// A screen or page machine has nothing to read on a day without activity; a chat machine always may try.
    private var hasNothingToRead: Bool {
        if let screen = model.source as? ScreenSource { return screen.sessions.isEmpty }
        if let pages = model.source as? PageSource { return pages.pageReading.pages.isEmpty }
        if let mail = model.source as? MailSource { return mail.mailReading.parts.isEmpty }
        return false
    }
}

/// What the day's source holds and what reading sends, with the switches the source needs.
struct ReadNote: View {
    let model: HelperModel
    @Environment(ModelSettings.self) private var models
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
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

    private var note: String {
        if let screen = model.source as? ScreenSource { return screenNote(screen) }
        if let pages = model.source as? PageSource { return pageNote(pages) }
        if let mail = model.source as? MailSource { return mailNote(mail) }
        return
            "Reading sends this day's messages, and the text in its photos (read on this Mac), to \(models.choice.title). Each call is listed in Settings › Advanced."
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

    private func mailNote(_ source: MailSource) -> String {
        let reading = source.mailReading
        let label = source.labels.joined(separator: ", ")
        guard !reading.parts.isEmpty else {
            return
                "No mail from \(label) on this day. Threads come from the Workbench browser extension while you open them in \(label) in Gmail."
        }
        let left =
            reading.leftOut == 0 ? "" : " \(reading.leftOut) later parts are past the size limit and are left out."
        return
            "\(source.threadsOpened) threads opened in \(label); \(reading.parts.count) messages and deck pages. Reading sends their text to \(models.choice.title).\(left) Threads you never opened cannot be seen."
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

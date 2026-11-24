import SwiftUI
import WorkbenchCore

struct ReadBar: View {
    let model: HelperModel

    var body: some View {
        HStack(spacing: Space.m) {
            Button(model.spec.source.readVerb) { Task { await model.read() } }
                .buttonStyle(.primary)
                .disabled(model.phase == .reading || model.source.hasNothingToRead || model.isPaused)
            ReadPhaseLabel(phase: model.phase, items: model.spec.itemsNoun, droppedBecause: "not backed by the source")
            Spacer()
            if !model.isOutbound { ViewPicker(model: model) }
        }
    }
}

/// What a reading sends, in words, above the buttons that change what the source reads. Without words of its own, it
/// says what a reading of messages sends.
struct ReadNote<Actions: View>: View {
    let note: String?
    let actions: Actions
    @Environment(ModelSettings.self) private var models

    init(note: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.note = note
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(note ?? messagesNote).textStyle(.callout).foregroundStyle(.supporting)
            actions
        }
    }

    private var messagesNote: String {
        "Reading sends this day's messages, and the text in its photos (read on this Mac), to \(models.choice.title). Each call is listed on the Usage page."
    }
}

extension ReadNote where Actions == EmptyView {
    init(note: String? = nil) { self.init(note: note) { EmptyView() } }
}

extension WhatsAppSource {
    func settingsView(for model: HelperModel) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: Space.l) {
                ReadNote { Button("Change chats", action: change) }
                ChosenChats(model: model, source: self)
                TeamPicker(model: model, source: self)
            })
    }
}

extension TelegramSource {
    func settingsView(for model: HelperModel) -> AnyView { AnyView(TelegramReadNote(model: model, source: self)) }
}

private struct TelegramReadNote: View {
    let model: HelperModel
    let source: TelegramSource
    @Environment(ModelSettings.self) private var models

    var body: some View {
        ReadNote(note: note) {
            HStack {
                Button("Change group", action: source.change)
                Button("Ask everyone again") {
                    Task {
                        do { try await source.askAgain() } catch { model.problems.report("ask again", error) }
                    }
                }
                Button("Stop reading this group") { model.attempt("stop reading the group", source.stopReading) }
            }
        }
    }

    private var note: String? {
        source.consent.map { consent in
            "Reading sends this day's messages of \(source.chat?.title ?? "the group") to \(models.choice.title). Everyone in it agreed on \(consent.at.formatted(date: .abbreviated, time: .omitted)). If anyone stops agreeing, stop reading this group."
        }
    }
}

extension PageSource {
    func settingsView(for model: HelperModel) -> AnyView { AnyView(PageReadNote(model: model, source: self)) }
}

private struct PageReadNote: View {
    let model: HelperModel
    let source: PageSource
    @Environment(ModelSettings.self) private var models
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        ReadNote(note: note) {
            HStack {
                if !capture.isOn(.screenText) {
                    Button("Turn on Screen text") { capture.set(.screenText, on: true) }
                }
                Button("Change sites") { model.attempt("clear the sites") { try source.choose("") } }
            }
        }
    }

    private var note: String {
        let reading = source.pageReading
        guard !reading.pages.isEmpty else {
            return
                "No page text from these sites on this day. Pages come from the Workbench browser extension while Screen text is on."
        }
        let left =
            reading.leftOut == 0 ? "" : " \(reading.leftOut) later pages are past the size limit and are left out."
        return "\(reading.pages.count) page views. Reading sends their text to \(models.choice.title).\(left)"
    }
}

extension MailSource {
    func settingsView(for model: HelperModel) -> AnyView { AnyView(MailReadNote(source: self)) }
}

private struct MailReadNote: View {
    let source: MailSource
    @Environment(ModelSettings.self) private var models

    var body: some View { ReadNote(note: note) }

    private var note: String {
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
}

extension ScreenSource {
    func settingsView(for model: HelperModel) -> AnyView { AnyView(ScreenReadNote(source: self)) }
}

private struct ScreenReadNote: View {
    let source: ScreenSource
    @Environment(ModelSettings.self) private var models
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        ReadNote(note: note) {
            if !capture.isOn(.screen) {
                Button("Turn on Screen") { capture.set(.screen, on: true) }
                    .help("Workbench keeps which app, window and page you are in. Never pixels or keystrokes.")
            }
        }
    }

    private var note: String {
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

import SwiftUI
import WorkbenchCore

struct CallsPage: View {
    private static let days = 7

    @Environment(CaptureSettings.self) private var capture
    @Environment(CallNotes.self) private var notes
    @Environment(TodayModel.self) private var today

    var body: some View {
        Page(
            intro: .calls,
            title: SidebarSelection.calls.title,
            subtitle: "Calls recorded on this Mac, with a transcript and notes. Start and stop one from the menu bar.",
            look: SidebarSelection.calls.look
        ) {
            OfferBanner()
            UpcomingMeetings()
            SpeechBanner()
            if let problem = notes.problem { Text(problem).foregroundStyle(Tone.bad.color).textStyle(.callout) }
            if let call = capture.call { RecordingNowLabel(call: call) }
            let recordings = capture.recordings(
                since: Calendar.current.date(byAdding: .day, value: -Self.days, to: .now)!
            )
            .filter { $0.state != .recording }
            if recordings.isEmpty {
                Text("No call recorded in the last \(Self.days) days.").foregroundStyle(.supporting)
            }
            ForEach(
                Dictionary(grouping: recordings) { Calendar.current.startOfDay(for: $0.startedAt) }.sorted {
                    $0.key > $1.key
                }, id: \.key
            ) { day, calls in
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(day.formatted(.dateTime.weekday(.wide).day().month())).textStyle(.headline)
                    ForEach(calls.sorted { $0.startedAt > $1.startedAt }) { CallCard(recording: $0) }
                }
                Divider()
            }
        }
        .task { await notes.start() }
        .task { await today.refreshMeetings() }
    }
}

private struct UpcomingMeetings: View {
    @Environment(TodayModel.self) private var today
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        let meetings = today.meetings.meetings.filter { $0.end > .now }.sorted { $0.start < $1.start }
        if !meetings.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Meetings today").textStyle(.headline)
                ForEach(meetings) { meeting in
                    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                        Text(meeting.start.formatted(date: .omitted, time: .shortened))
                            .foregroundStyle(.supporting).monospacedDigit().frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(meeting.title.isEmpty ? "Untitled" : meeting.title).fontWeight(.semibold)
                            Text(detail(meeting)).textStyle(.callout).foregroundStyle(.supporting)
                        }
                        Spacer(minLength: Space.m)
                        JoinButton(meeting: meeting)
                    }
                }
            }
            Divider()
        } else if today.meetings.offersMeetings {
            HStack(spacing: Space.m) {
                Label("See today's meetings here, with a button to join each one.", systemImage: "calendar")
                    .foregroundStyle(.supporting)
                Spacer(minLength: Space.m)
                Button("Show my meetings") {
                    capture.set(.calendar, on: true)
                    Task { await today.refreshMeetings() }
                }
            }
            .textStyle(.callout)
        }
    }

    private func detail(_ meeting: Meeting) -> String {
        let until = "until \(meeting.end.formatted(date: .omitted, time: .shortened))"
        let place = meeting.joinService ?? meeting.joinURL?.host()
        return ([until] + [place].compactMap(\.self)).joined(separator: " · ")
    }
}

private struct OfferBanner: View {
    @Environment(CallWatcher.self) private var watcher

    var body: some View {
        if let offer = watcher.offer {
            HStack(spacing: Space.m) {
                Image(systemName: "record.circle").foregroundStyle(Tone.bad.color)
                Text("A \(offer.source.label) call is on. Record it?").fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.s)
                Button("Not now", action: watcher.dismiss).buttonStyle(.ghost)
                Button("Always record in \(offer.app.name)", action: watcher.recordAlways).buttonStyle(.ghost)
                Button("Record", action: watcher.record).buttonStyle(.primary)
            }
            .padding(Space.m)
            .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
        }
    }
}

private struct SpeechBanner: View {
    @Environment(CallNotes.self) private var notes

    var body: some View {
        switch notes.speech {
        case .checking, .ready: EmptyView()
        case .needsDownload:
            banner("Transcripts use Apple's English speech model, which runs on this Mac. It's a one-time download.") {
                Button("Download") { Task { await notes.download() } }.buttonStyle(.primary)
            }
        case .downloading:
            banner("Downloading the English speech model…") { ProgressView().controlSize(.small) }
        case .unavailable(let reason):
            banner(reason) { EmptyView() }
        }
    }

    private func banner(_ text: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: "text.bubble").foregroundStyle(.iconTint)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            action()
        }
        .padding(Space.m)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }
}

private struct CallCard: View {
    let recording: Recording
    @Environment(CallNotes.self) private var notes
    @Environment(IdentityModel.self) private var identity

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            header
            if recording.state == .failed {
                Text(recording.error ?? "Failed").foregroundStyle(Tone.bad.color).textSelection(.enabled)
            } else {
                PlaybackProblem(recording: recording)
                notesBody
            }
        }
        .textStyle(.callout)
        .padding(Space.m)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.s) {
            Text(recording.source.service).textStyle(.body, weight: .semibold)
            if !recording.source.title.isEmpty {
                Text(recording.source.title).textStyle(.body).lineLimit(1)
            }
            Text(recording.startedAt.formatted(date: .omitted, time: .shortened)).foregroundStyle(.supporting)
            Spacer(minLength: Space.m)
            if recording.state == .saved {
                CallPlayer(recording: recording)
                RevealButton(folder: recording.folder)
            } else {
                Text(span).foregroundStyle(.supporting).monospacedDigit()
            }
        }
    }

    @ViewBuilder private var notesBody: some View {
        let note = notes.notes[recording.id]
        if let summary = note?.summary {
            SummaryView(summary: summary)
        } else if let error = note?.summaryError {
            failure("The notes were not written: \(error)")
        } else if notes.working.contains(recording.id) {
            Label(note?.transcript == nil ? "Transcribing…" : "Writing notes…", systemImage: "hourglass")
                .foregroundStyle(.supporting)
        } else if note == nil, notes.speech == .ready {
            Label("Waiting to transcribe", systemImage: "clock").foregroundStyle(.supporting)
        }
        if let error = note?.transcriptError {
            if error == CallNotes.noSpeech {
                Text(error).foregroundStyle(.supporting)
            } else {
                failure("The transcript was not made: \(error)")
            }
        }
        if let lines = note?.transcript {
            Fold("Transcript · \(lines.count) turns") {
                TranscriptView(recording: recording, lines: lines, me: founderLabel(identity.identity.name))
            }
            .padding(.top, Space.xs)
        }
    }

    private func failure(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).foregroundStyle(Tone.bad.color).textSelection(.enabled)
            Spacer()
            Button("Try again") { Task { await notes.retry(recording) } }.buttonStyle(.ghost)
        }
    }

    private var span: String {
        let start = recording.startedAt.formatted(date: .omitted, time: .shortened)
        guard let end = recording.endedAt else { return start }
        return "\(start) · \(CallTranscript.clock(end.timeIntervalSince(recording.startedAt)))"
    }
}

private struct SummaryView: View {
    let summary: CallSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(summary.summary).textStyle(.body).fixedSize(horizontal: false, vertical: true)
            if !summary.decisions.isEmpty {
                list("Decided", summary.decisions.map { Text($0) })
            }
            if !summary.actions.isEmpty {
                list("To do", summary.actions.map { Text("\($0.owner): ").bold() + Text($0.text) })
            }
        }
        .textSelection(.enabled)
    }

    private func list(_ title: String, _ rows: [Text]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).textStyle(.callout, weight: .semibold).foregroundStyle(.supporting)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("•").foregroundStyle(.supporting)
                    row.fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct TranscriptView: View {
    let recording: Recording
    let lines: [CallLine]
    let me: String
    @Environment(CallPlayback.self) private var playback

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Button(CallTranscript.clock(line.start)) {
                        Task { await playback.seek(recording, to: line.start, andPlay: true) }
                    }
                    .buttonStyle(.plain).foregroundStyle(.linkText).monospacedDigit()
                    .pointerStyle(.link).help("Play from here")
                    .frame(width: 52, alignment: .leading)
                    (Text(line.speaker == .me ? me : recording.them).bold() + Text("  " + line.text))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .textSelection(.enabled)
        .padding(.top, Space.xs)
    }
}

private struct CallPlayer: View {
    let recording: Recording
    @Environment(CallPlayback.self) private var playback
    @State private var dragged: Double?

    var body: some View {
        let isCurrent = playback.isCurrent(recording)
        let total = isCurrent && playback.duration > 0 ? playback.duration : spoken
        let now = dragged ?? (isCurrent ? playback.time : 0)
        HStack(spacing: Space.xs) {
            Button {
                Task { await playback.toggle(recording) }
            } label: {
                Image(systemName: isCurrent && playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10)).frame(width: 12, height: 12)
            }
            .buttonStyle(.ghost)
            .help(isCurrent && playback.isPlaying ? "Pause" : "Play")
            .accessibilityLabel(isCurrent && playback.isPlaying ? "Pause" : "Play")
            Text(CallTranscript.clock(now)).fixedSize()
            Slider(
                value: Binding(get: { now }, set: { dragged = $0 }), in: 0...max(total, 1),
                onEditingChanged: { editing in
                    guard !editing, let target = dragged else { return }
                    Task {
                        await playback.seek(recording, to: target)
                        dragged = nil
                    }
                }
            )
            .controlSize(.mini)
            .frame(width: 160)
            .accessibilityLabel("Position in the call")
            Text(CallTranscript.clock(total)).fixedSize()
        }
        .textStyle(.caption, digits: true)
        .foregroundStyle(.supporting)
    }

    private var spoken: Double {
        recording.endedAt.map { $0.timeIntervalSince(recording.startedAt) } ?? 0
    }
}

private struct PlaybackProblem: View {
    let recording: Recording
    @Environment(CallPlayback.self) private var playback

    var body: some View {
        if playback.isCurrent(recording), let problem = playback.problem {
            Text(problem).foregroundStyle(Tone.bad.color)
        }
    }
}

private struct RevealButton: View {
    let folder: URL
    @State private var isHovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } label: {
            Image(systemName: "folder")
                .font(.system(size: 13, weight: isHovered ? .bold : .regular))
                .foregroundStyle(isHovered ? Color.sidebarHotIcon : .sidebarIcon)
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.ghost)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .help("Reveal in Finder")
        .accessibilityLabel("Reveal in Finder")
    }
}

struct RecordingNowLabel: View {
    let call: Recording

    var body: some View {
        Label(
            "Recording \(call.source.label) since \(call.startedAt.formatted(date: .omitted, time: .shortened))",
            systemImage: "record.circle"
        )
        .foregroundStyle(Tone.bad.color)
    }
}

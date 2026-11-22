import SwiftUI
import WorkbenchCore

struct MeetingsSection: View {
    let model: TodayModel

    var body: some View {
        TodaySection("Meetings", count: model.meetingCards.count) {
            ForEach(model.meetingCards) { MeetingRow(card: $0, model: model).transition(.opacity) }
        }
    }
}

struct MeetingRow: View {
    let card: MeetingCard
    let model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            summary
            ForEach(card.preps) { PrepView(prep: $0, model: model) }
                .padding(.leading, 64 + Space.m)
        }
        .padding(.vertical, Space.xs)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(card.meeting.start.formatted(date: .omitted, time: .shortened))
                .textStyle(.callout).foregroundStyle(.supporting).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(card.meeting.title.isEmpty ? "Untitled" : card.meeting.title).fontWeight(.semibold)
                if !who.isEmpty { Text(who).textStyle(.callout).foregroundStyle(.supporting) }
            }
        }
    }

    private var who: String {
        card.meeting.guests.map { $0.name.isEmpty ? $0.email : $0.name }.formatted(.list(type: .and, width: .narrow))
    }
}

private struct PrepView: View {
    let prep: Prep
    let model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Text(prep.name).fontWeight(.semibold)
                if let stage = prep.stage { Text(stage).textStyle(.caption).foregroundStyle(.supporting) }
            }
            if let line = prep.line { Text(line).foregroundStyle(.supporting) }
            ForEach(prep.facts) { FactLine(item: $0, model: model) }
            ForEach(prep.quotes, id: \.text) { quote in
                Text("“\(quote.text)” · \(quote.source)").textStyle(.callout).foregroundStyle(.supporting)
                    .textSelection(.enabled)
            }
        }
    }
}

struct MeetingsOffer: View {
    let model: TodayModel
    @Environment(CaptureSettings.self) private var capture

    var body: some View {
        HStack(spacing: Space.m) {
            Label("See today's meetings here, with what you know about the people in them.", systemImage: "calendar")
                .foregroundStyle(.supporting)
            Spacer(minLength: Space.m)
            Button("Show today's meetings", action: turnOn)
            Button("Not now", action: model.meetings.declineOffer).buttonStyle(.ghost)
        }
        .textStyle(.callout)
    }

    private func turnOn() {
        capture.set(.calendar, on: true)
        Task { await model.refreshMeetings() }
    }
}

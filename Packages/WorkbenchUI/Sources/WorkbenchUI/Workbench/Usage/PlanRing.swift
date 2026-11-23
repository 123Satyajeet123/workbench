import SwiftUI
import WorkbenchCore

struct PlanRing: View {
    let window: PlanLimits.Window?
    var size: CGFloat = 28
    var symbol = "asterisk"

    var body: some View {
        ZStack {
            Circle().stroke(Color.dividerLine, lineWidth: line)
            if let window {
                Circle().trim(from: 0, to: min(max(window.used, 0.02), 1))
                    .stroke(Self.tone(of: window), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: symbol).font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(Color.orange)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            window.map { "\(Self.percent($0.used)) of the Claude plan used" } ?? "Claude plan use unknown")
    }

    private var line: CGFloat { max(2, size / 9) }

    static func tone(of window: PlanLimits.Window) -> Color {
        if window.isAtLimit || window.used >= 1 { return Tone.bad.color }
        return window.used >= 0.8 ? Tone.attention.color : Tone.good.color
    }

    static func percent(_ used: Double) -> String {
        (min(max(used, 0), 1)).formatted(.percent.precision(.fractionLength(0)))
    }
}

extension PlanLimits {
    var summary: String {
        var lines: [String] = []
        if let fiveHour { lines.append("5-hour: \(fiveHour.line)") }
        if let week { lines.append("Week: \(week.line)") }
        lines.append("As of \(at.formatted(date: .omitted, time: .shortened))")
        return lines.joined(separator: "\n")
    }
}

extension PlanLimits.Window {
    var line: String {
        let used = PlanRing.percent(used)
        guard let resetsAt else { return used }
        let when =
            Calendar.current.isDateInToday(resetsAt)
            ? resetsAt.formatted(date: .omitted, time: .shortened)
            : resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(used) · resets \(when)"
    }
}

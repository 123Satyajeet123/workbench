import SwiftUI
import WorkbenchCore

/// The agreement report. Every number is on the held-out set, and says so.
struct AgreementReportView: View {
    let report: AgreementReport

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Agreement with your calls · held-out set").textStyle(.headline)
            if report.total == 0 {
                Text("Read at least one deal to see agreement.").textStyle(.callout).foregroundStyle(.supporting)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.xs) {
                    line("Agreement", "\(report.agreed) of \(report.total)\(percent(report.rate))", "held-out")
                    line("Floor (90% sure)", percent(report.agreementFloor, atLeast: true), "held-out, exact binomial")
                    line(
                        "Best level missed",
                        "\(report.topMissed) of \(report.calledTop) you called \(report.levels.first?.name ?? "")",
                        "held-out")
                    line(
                        "Most best-level missed (90% sure)", percent(report.topMissedCeiling, atMost: true),
                        "held-out, exact binomial")
                    line("Needs your review", "\(report.needingReview) of \(report.total)", "held-out")
                }
                .textStyle(.callout)
                ConfusionGrid(report: report)
                if report.unread > 0 { note("Not read yet and left out: \(report.unread).") }
                if report.needingReading > 0 {
                    note("Read before a rule changed, so read again: \(report.needingReading).")
                }
            }
        }
    }

    private func line(_ name: String, _ value: String, _ split: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.supporting)
            Text(value)
            Text(split).textStyle(.caption).foregroundStyle(.supporting)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).textStyle(.callout).foregroundStyle(Tone.attention.color)
    }

    private func percent(_ value: Double?, atLeast: Bool = false, atMost: Bool = false) -> String {
        guard let value else { return "" }
        let text = value.formatted(.percent.precision(.fractionLength(0)))
        return atLeast ? "at least \(text)" : atMost ? "at most \(text)" : " (\(text))"
    }
}

struct ConfusionGrid: View {
    let report: AgreementReport

    private func isTopMissed(_ called: Level, _ rated: Level) -> Bool {
        called == report.levels.first && rated == report.levels.last
    }

    var body: some View {
        Grid(horizontalSpacing: Space.l, verticalSpacing: Space.xs) {
            GridRow {
                Text("You \\ us").textStyle(.caption).foregroundStyle(.supporting)
                ForEach(report.levels) { Text($0.name).textStyle(.caption).foregroundStyle(.supporting) }
            }
            ForEach(report.levels) { called in
                GridRow {
                    Text(called.name).textStyle(.caption).foregroundStyle(.supporting)
                    ForEach(report.levels) { rated in
                        let count = report.count(called: called.name, rated: rated.name)
                        Text("\(count)").textStyle(.callout, digits: true)
                            .fontWeight(called == rated ? .semibold : .regular)
                            .foregroundStyle(isTopMissed(called, rated) && count > 0 ? Tone.bad.color : .primary)
                    }
                }
            }
        }
    }
}

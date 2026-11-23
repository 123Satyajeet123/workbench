import Charts
import SwiftUI
import WorkbenchCore

struct UsagePage: View {
    enum Breakdown: String, CaseIterable {
        case model = "Model"
        case machine = "Machine"
        case day = "Day"
    }

    @Environment(RunsModel.self) private var runs
    @Environment(PlanUsage.self) private var planUsage
    @Environment(ModelSettings.self) private var models
    @Environment(Crew.self) private var crew
    @State private var days = 30
    @State private var breakdown = Breakdown.model

    var body: some View {
        let report = UsageReport(runs: runs.runs, days: days, now: .now, name: crew.usageName(ofTask:))
        Page(title: SidebarSelection.usage.title) {
            Picker("Period", selection: $days) {
                ForEach([7, 30, 90], id: \.self) { Text("\($0) days").tag($0) }
            }
            .labelsHidden().fixedSize()
        } content: {
            if let problem = runs.problem ?? planUsage.problem {
                Text(problem).foregroundStyle(Tone.bad.color)
            }
            if models.billing == .plan { PlanLimitsRow(limits: planUsage.limits) }
            HStack(alignment: .top, spacing: Space.xl) {
                total(report).frame(width: 220, alignment: .leading)
                chart(report)
            }
            breakdownTable(report)
            VStack(alignment: .leading, spacing: Space.m) {
                Fold("Token details") { totals(report.total) }
                Fold("Quality of each machine's entries") { QualitySection() }
                Fold("All calls · \(report.calls)") { CallsSection(runs: report.runs) }
            }
        }
        .onAppear(perform: runs.refresh)
    }

    private func total(_ report: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(report.total.costUSD.usageCost)
                    .font(.system(size: 40, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                Image(systemName: "info.circle").foregroundStyle(.supporting)
                    .help(
                        "Cost is at list price, as Claude reports it. On a Claude plan it is what the calls would cost, not what you pay. Codex reports tokens only."
                    )
                    .accessibilityLabel("Cost is a list-price estimate")
            }
            Text("\(report.calls) \(report.calls == 1 ? "call" : "calls")").foregroundStyle(.supporting)
        }
    }

    private func chart(_ report: UsageReport) -> some View {
        Chart(report.byDay) { day in
            AreaMark(x: .value("Day", day.day, unit: .day), y: .value("Cost", day.usage.costUSD))
                .foregroundStyle(Color.orange.opacity(0.15)).interpolationMethod(.monotone)
            LineMark(x: .value("Day", day.day, unit: .day), y: .value("Cost", day.usage.costUSD))
                .foregroundStyle(Color.orange).interpolationMethod(.monotone)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let number = value.as(Double.self) { Text(number.usageCost) } }
            }
        }
        .frame(maxWidth: .infinity).frame(height: 140)
        .accessibilityLabel("Daily cost over the last \(days) days")
    }

    private func breakdownTable(_ report: UsageReport) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                Text("Breakdown").textStyle(.headline)
                Spacer()
                Picker("Breakdown", selection: $breakdown) {
                    ForEach(Breakdown.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            let rows = rows(of: report)
            if rows.isEmpty {
                Text("No model calls in the last \(days) days.").foregroundStyle(.supporting)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.s) {
                    ForEach(rows) { row in
                        GridRow {
                            Text(row.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.costText).gridColumnAlignment(.trailing)
                            Text(share(row.usage, of: report.total)).foregroundStyle(.supporting)
                                .gridColumnAlignment(.trailing)
                            Text("\(row.usage.tokensText) tokens").foregroundStyle(.supporting)
                                .gridColumnAlignment(.trailing)
                        }
                        .monospacedDigit()
                    }
                }
            }
        }
    }

    private func totals(_ usage: Usage) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Space.xl, verticalSpacing: Space.m) {
            GridRow {
                figure("Tokens without cache reads", usage.tokensWithoutCacheReads)
                figure("Tokens with cache reads", usage.tokens)
                figure("Cached input", usage.cacheReadTokens)
            }
            GridRow {
                figure("Uncached input", usage.inputTokens)
                figure("Cache creation", usage.cacheWriteTokens)
                figure("Output", usage.outputTokens)
            }
        }
        .padding(.top, Space.s)
    }

    private func figure(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).textStyle(.callout).foregroundStyle(.supporting)
            Text(value.formatted(.number.notation(.compactName))).monospacedDigit()
        }
    }

    private func rows(of report: UsageReport) -> [UsageReport.Row] {
        switch breakdown {
        case .model: report.byModel
        case .machine: report.byMachine
        case .day:
            report.byDay.reversed().filter { $0.usage.tokens > 0 }.map { day in
                UsageReport.Row(
                    name: day.day.formatted(.dateTime.weekday(.abbreviated).day().month()), usage: day.usage)
            }
        }
    }

    private func share(_ part: Usage, of total: Usage) -> String {
        guard total.costUSD > 0, part.costUSD > 0 else { return "" }
        return (part.costUSD / total.costUSD).formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct PlanLimitsRow: View {
    let limits: PlanLimits?
    @Environment(PlanUsage.self) private var planUsage

    var body: some View {
        HStack(spacing: Space.xl) {
            window("5-hour", limits?.fiveHour)
            window("Week", limits?.week)
            Spacer()
            Button {
                Task { await planUsage.refresh() }
            } label: {
                if planUsage.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.ghost).disabled(planUsage.isRefreshing)
            .help(
                "\(limits.map { "As of \($0.at.formatted(date: .omitted, time: .shortened)). " } ?? "")Check your Claude plan now. Sends one tiny request to Claude Haiku."
            )
            .accessibilityLabel("Check your Claude plan now")
        }
    }

    private func window(_ title: String, _ window: PlanLimits.Window?) -> some View {
        HStack(spacing: Space.s) {
            PlanRing(window: window, size: 22, symbol: "")
            Text("\(title) ").foregroundStyle(.supporting) + Text(window?.line ?? "not known yet").monospacedDigit()
        }
    }
}

extension UsageReport.Row {
    var costText: String { usage.costUSD == 0 && usage.tokens > 0 ? "—" : usage.costUSD.usageCost }
}

extension Double {
    var usageCost: String {
        abs(self) >= 1 || self == 0
            ? formatted(.currency(code: "USD").precision(.fractionLength(2)))
            : formatted(.currency(code: "USD").precision(.significantDigits(1...3)))
    }
}

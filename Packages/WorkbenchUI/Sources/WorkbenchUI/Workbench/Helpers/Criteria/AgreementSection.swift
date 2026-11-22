import SwiftUI
import WorkbenchCore

struct AgreementSection: View {
    let agreement: HelperAgreement

    var body: some View {
        Fold("Held-out deals · \(agreement.deals.count)") {
            AgreementBody(agreement: agreement).padding(.top, Space.m)
        }
        .textStyle(.headline)
    }
}

struct AgreementBody: View {
    let agreement: HelperAgreement
    @State private var company = ""
    @State private var text = ""
    @State private var url = ""
    @State private var call = Rating.hot

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(
                "Past deals with your own call. They are never used to tune the machine: they only measure how often its call matches yours."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            ForEach(agreement.report.rows) { row in DealRow(row: row) { agreement.remove(row.deal) } }
            ForEach(agreement.deals.filter { $0.reading == nil }) { deal in
                HStack {
                    Text("\(deal.company) · you said \(deal.call.rawValue) · not read yet")
                        .textStyle(.callout).foregroundStyle(.supporting)
                    Spacer()
                    Button("Remove") { agreement.remove(deal) }.buttonStyle(.ghost).foregroundStyle(.linkText)
                }
            }
            addForm
            HStack {
                Button(agreement.isReading ? "Reading…" : "Read waiting deals (\(agreement.waiting.count))") {
                    Task { await agreement.read() }
                }
                .disabled(agreement.isReading || agreement.waiting.isEmpty)
                .help("Sends each deal's text to the model you chose, to judge your rules. Nothing else is read.")
            }
            AgreementReportView(report: agreement.report)
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                TextField("Company", text: $company).frame(maxWidth: 200)
                TextField("Deck link, for your reference", text: $url).frame(maxWidth: 260)
                Picker("Your call", selection: $call) {
                    ForEach(Rating.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 220)
            }
            TextEditor(text: $text).frame(height: 90).border(.quaternary)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste the deck or pitch text here").foregroundStyle(.tertiary).padding(Space.xs)
                            .allowsHitTesting(false)
                    }
                }
            Button("Add held-out deal") {
                agreement.add(company: company, text: text, url: url, call: call)
                (company, text, url) = ("", "", "")
            }
            .disabled(company.cleaned == nil || text.cleaned == nil)
        }
    }
}

private struct DealRow: View {
    let row: AgreementReport.Row
    let remove: () -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: row.agrees ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle((row.agrees ? Tone.good : Tone.bad).color)
                .accessibilityLabel(row.agrees ? "Agrees" : "Differs")
            Text(row.deal.company)
            Text("you: \(row.deal.call.rawValue) · us: \(row.triage.rating.rawValue)")
                .textStyle(.callout).foregroundStyle(.supporting)
            if row.triage.needsReview { Text("needs review").textStyle(.caption).foregroundStyle(Tone.attention.color) }
            if row.needsReading { Text("rules changed: read again").textStyle(.caption).foregroundStyle(.supporting) }
            Spacer()
            Button("Remove", action: remove).buttonStyle(.ghost).foregroundStyle(.linkText)
        }
    }
}

import SwiftUI
import WorkbenchCore

/// Asks why the investor passed and when to look again, before the deal moves to its watch stage. The revisit day is a
/// dated fact on Today; the investor may pass with no revisit.
struct PassedDealForm: View {
    let deal: WorkObject
    let cancel: () -> Void
    @Environment(DealsModel.self) private var deals
    @State private var reason = ""
    @State private var revisits = true
    @State private var day =
        Calendar.current.date(byAdding: .month, value: RunSettings.standard.revisitMonths, to: .now) ?? .now

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Pass on \(deal.name)").textStyle(.title3)
            TextField("Why you pass, for example: no revenue", text: $reason).onSubmit(save)
            Toggle("Remind me to look again", isOn: $revisits)
            if revisits {
                DatePicker("Look again on", selection: $day, displayedComponents: .date)
            }
            Text(
                "The reason is kept as a note on the deal. On the day, Today shows the deal with any news about the company since you passed. The company is followed in the news from now on."
            )
            .textStyle(.callout).foregroundStyle(.supporting)
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Pass", action: save).buttonStyle(.borderedProminent)
            }
        }
        .padding(Space.l).zoomedWidth(440)
    }

    private func save() {
        deals.pass(deal, reason: reason, revisit: revisits ? WorkDay(containing: noon(of: day)) : nil)
        cancel()
    }

    private func noon(of date: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}

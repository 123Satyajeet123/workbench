import Foundation
import Observation
import WorkbenchCore

@Observable
final class HelperAgreement {
    private(set) var deals: [PastDeal] = []
    private(set) var isReading = false

    @ObservationIgnored private let context: MachineContext

    init(context: MachineContext) {
        self.context = context
        load()
    }

    var report: AgreementReport { AgreementReport(deals: deals, criteria: context.spec.criteria ?? Criteria()) }

    var waiting: [PastDeal] {
        let stale = Set(report.rows.filter(\.needsReading).map(\.id))
        return deals.filter { $0.reading == nil || stale.contains($0.id) }
    }

    func add(company: String, text: String, url: String, call: Rating) {
        guard let company = company.cleaned, let text = text.cleaned else { return }
        deals.append(PastDeal(company: company, text: text, url: url.cleaned, call: call))
        save()
    }

    func remove(_ deal: PastDeal) {
        deals.removeAll { $0.id == deal.id }
        save()
    }

    func read() async {
        guard !isReading, !waiting.isEmpty else { return }
        isReading = true
        defer { isReading = false }
        do {
            let reader = AgreementReader(
                spec: context.spec, model: context.makeModel(try context.runner(for: .init(context.spec))))
            for deal in waiting {
                let read = try await reader.read(deal, on: context.today)
                if let index = deals.firstIndex(where: { $0.id == deal.id }) { deals[index] = read }
                save()
            }
        } catch {
            context.problems.report("read the past deals", error)
        }
    }

    private func load() {
        context.problems.attempt("read the past deals") {
            deals = try MachineKey.agreement(context.spec.task).load(from: context.store) ?? []
        }
    }

    private func save() {
        context.problems.attempt("save the past deals") {
            try MachineKey.agreement(context.spec.task).save(deals, to: context.store)
        }
    }
}

import Foundation

extension HelperSpec {
    public var computedField: String? {
        fields.first { $0.kind.isComputed }?.name
    }

    public func triage(of item: Item) -> Triage? { criteria?.triage(item.fields) }

    public func scored(_ item: Item) -> Item {
        guard let name = computedField, let triage = triage(of: item) else { return item }
        var scored = item
        scored.fields[name] = triage.rating.rawValue
        return scored
    }
}

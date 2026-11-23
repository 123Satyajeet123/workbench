import Foundation

extension HelperSpec {
    public var computedField: String? {
        fields.first { $0.kind.isComputed }?.name
    }

    /// The call on an item under this spec's criteria; nil for a spec with none.
    public func triage(of item: Item) -> Triage? { criteria?.triage(item.fields) }

    /// The item with its computed field set from its rule readings. The call is never stored: it follows the criteria
    /// as they are now, so an edit changes it with no new reading.
    public func scored(_ item: Item) -> Item {
        guard let name = computedField, let triage = triage(of: item) else { return item }
        var scored = item
        scored.fields[name] = triage.rating.rawValue
        return scored
    }
}

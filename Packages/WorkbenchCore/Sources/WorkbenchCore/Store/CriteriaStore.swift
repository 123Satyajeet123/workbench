import Foundation

extension Store {
    public func setCriteria(_ machine: Machine, _ criteria: Criteria) throws {
        guard criteria.problem == nil else { return }
        var spec = machine.spec
        spec.criteria = criteria
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }
}

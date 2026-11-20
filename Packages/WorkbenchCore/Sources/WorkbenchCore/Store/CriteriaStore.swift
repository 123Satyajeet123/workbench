import Foundation

extension Store {
    /// Saves the investor's criteria for a machine. Like a brief edit, it changes the machine's instructions, so the
    /// next reading is a new prompt version that earns trust again. Criteria with a problem are refused.
    public func setCriteria(_ machine: Machine, _ criteria: Criteria) throws {
        guard criteria.problem == nil else { return }
        var spec = machine.spec
        spec.criteria = criteria
        try change(machine, name: machine.name, spec: spec, state: machine.state)
    }
}

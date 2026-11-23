/// What the window's one right panel shows.
enum PanelContent: Equatable {
    case fact, playbook, hidden

    /// A fact in the panel wins. With none, the panel shows the page's Playbook when the page has one and the person
    /// has not closed the panel.
    static func of(hasFact: Bool, hasPlaybook: Bool, isOn: Bool) -> PanelContent {
        if hasFact { return .fact }
        return hasPlaybook && isOn ? .playbook : .hidden
    }
}

/// The panel's switch. Closing a panel that holds a fact closes the fact; the panel then shows the Playbook if the
/// page has one. Closing a panel that holds the Playbook hides it until the person opens it again.
struct PanelSwitch: Equatable {
    var isOn = true

    mutating func toggle(hasFact: Bool, closeFact: () -> Void) {
        if hasFact { closeFact() } else { isOn.toggle() }
    }
}

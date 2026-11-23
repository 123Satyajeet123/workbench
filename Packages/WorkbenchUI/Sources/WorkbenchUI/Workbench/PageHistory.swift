struct PageHistory: Equatable {
    static let limit = 50

    private(set) var back: [SidebarSelection] = []
    private(set) var forward: [SidebarSelection] = []

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }

    mutating func visit(from page: SidebarSelection) {
        back.append(page)
        if back.count > Self.limit { back.removeFirst(back.count - Self.limit) }
        forward.removeAll()
    }

    mutating func goBack(from current: SidebarSelection, isOpen: (SidebarSelection) -> Bool = { _ in true })
        -> SidebarSelection?
    {
        while let page = back.popLast() {
            guard isOpen(page) else { continue }
            forward.append(current)
            return page
        }
        return nil
    }

    mutating func goForward(from current: SidebarSelection, isOpen: (SidebarSelection) -> Bool = { _ in true })
        -> SidebarSelection?
    {
        while let page = forward.popLast() {
            guard isOpen(page) else { continue }
            back.append(current)
            return page
        }
        return nil
    }
}

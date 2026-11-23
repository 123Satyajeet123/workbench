import Foundation

struct PageTabs: Equatable {
    struct Tab: Identifiable, Equatable {
        let id = UUID()
        var page: SidebarSelection
        var history = PageHistory()
    }

    private(set) var tabs: [Tab]
    private var current: Int

    init(pages: [SidebarSelection] = [.mochi], current: Int = 0) {
        tabs = (pages.isEmpty ? [.mochi] : pages).map { Tab(page: $0) }
        self.current = min(max(current, 0), tabs.count - 1)
    }

    init(saved: String, isOpen: (SidebarSelection) -> Bool = { _ in true }) {
        let parts = saved.split(separator: "|", maxSplits: 1).map(String.init)
        let pages = (parts.last ?? "").split(separator: ",").compactMap { SidebarSelection(rawValue: String($0)) }
            .map { isOpen($0) ? $0 : .mochi }
        self.init(pages: pages, current: parts.count == 2 ? Int(parts[0]) ?? 0 : 0)
    }

    var saved: String { "\(current)|" + tabs.map(\.page.rawValue).joined(separator: ",") }
    var page: SidebarSelection { tabs[current].page }
    var selected: Tab.ID { tabs[current].id }
    var canGoBack: Bool { tabs[current].history.canGoBack }
    var canGoForward: Bool { tabs[current].history.canGoForward }
    var canClose: Bool { tabs.count > 1 }

    mutating func open(_ page: SidebarSelection) {
        guard page != self.page else { return }
        tabs[current].history.visit(from: self.page)
        tabs[current].page = page
    }

    mutating func openNewTab(_ page: SidebarSelection = .mochi) {
        current += 1
        tabs.insert(Tab(page: page), at: current)
    }

    mutating func close(_ id: Tab.ID) {
        guard canClose, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if index < current || current == tabs.count { current -= 1 }
    }

    mutating func select(_ id: Tab.ID) {
        if let index = tabs.firstIndex(where: { $0.id == id }) { current = index }
    }

    mutating func move(_ id: Tab.ID, by steps: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let to = min(max(from + steps, 0), tabs.count - 1)
        guard to != from else { return }
        let open = selected
        tabs.insert(tabs.remove(at: from), at: to)
        select(open)
    }

    mutating func selectNext() { current = (current + 1) % tabs.count }

    mutating func selectPrevious() { current = (current + tabs.count - 1) % tabs.count }

    mutating func goBack(isOpen: (SidebarSelection) -> Bool = { _ in true }) {
        if let page = tabs[current].history.goBack(from: page, isOpen: isOpen) { tabs[current].page = page }
    }

    mutating func goForward(isOpen: (SidebarSelection) -> Bool = { _ in true }) {
        if let page = tabs[current].history.goForward(from: page, isOpen: isOpen) { tabs[current].page = page }
    }
}

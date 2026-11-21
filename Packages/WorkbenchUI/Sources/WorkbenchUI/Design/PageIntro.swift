import SwiftUI

/// The pages whose introduction the person closed. Kept on this Mac in user defaults, as the zoom is; a closed one
/// comes back from the ⓘ beside its page's title.
struct DismissedIntros: RawRepresentable, Equatable {
    static let key = "dismissedIntros"

    private(set) var pages: Set<String> = []

    init() {}

    init?(rawValue: String) {
        pages = Set(rawValue.split(separator: ",").map(String.init))
    }

    var rawValue: String { pages.sorted().joined(separator: ",") }

    func contains(_ page: SidebarSelection) -> Bool { pages.contains(page.rawValue) }

    mutating func dismiss(_ page: SidebarSelection) { pages.insert(page.rawValue) }

    mutating func restore(_ page: SidebarSelection) { pages.remove(page.rawValue) }
}

/// A page's introduction: what the page is for, in a quiet callout under its title, with a cross to close it.
struct PageIntroCallout: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Image(systemName: "info.circle").foregroundStyle(.iconTint)
            Text(text).foregroundStyle(.supporting).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly).buttonStyle(.ghost).foregroundStyle(.iconTint)
                .help("Hide this note. The ⓘ beside the title brings it back.")
        }
        .padding(.leading, Space.m)
        .padding(.vertical, Space.s)
        .padding(.trailing, Space.s)
        .background(.calloutFill, in: .rect(cornerRadius: Radius.card))
    }
}

/// The ⓘ beside a page's title once its introduction is closed: it shows the introduction again.
struct PageIntroButton: View {
    let show: () -> Void

    var body: some View {
        Button("About this page", systemImage: "info.circle", action: show)
            .labelStyle(.iconOnly).buttonStyle(.ghost).foregroundStyle(.iconTint)
            .help("What this page is for")
    }
}

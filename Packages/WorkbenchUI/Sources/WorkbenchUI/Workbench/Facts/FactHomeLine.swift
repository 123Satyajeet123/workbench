import SwiftUI
import WorkbenchCore

/// Where a fact is filed, in one quiet line: "In Team", or "Filed to Deals?" with Confirm and Move to… while a model's
/// proposal waits for the person. Every surface that shows a fact draws its home with this line.
struct FactHomeLine: View {
    let item: Item
    let surface: MarkSurface
    /// Whether the line offers Move to… when no proposal waits. A row offers it in its own menu instead.
    var offersMove = false
    @Environment(FactHomes.self) private var homes: FactHomes?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let homes, let id = item.id {
                line(homes.standings[id], homes: homes, id: id)
                if let problem = homes.problems[id] {
                    Text(problem).textStyle(.callout).foregroundStyle(Tone.bad.color)
                }
            }
        }
        .task(id: item.id) {
            if let id = item.id { homes?.read(id) }
        }
    }

    @ViewBuilder private func line(_ standing: FactHomes.Standing?, homes: FactHomes, id: ItemID) -> some View {
        let proposed = standing?.proposed
        let home = standing?.home
        if proposed != nil || home != nil || offersMove {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                if let proposed {
                    Text("Filed to \(proposed.name)?").text(.meta)
                    Button("Confirm") { homes.confirm(id, surface: surface) }
                        .help("File it to \(proposed.name)")
                } else if let home {
                    Text("In \(home.name)").text(.meta)
                }
                if proposed != nil || offersMove {
                    MoveToMenu(items: [item], surface: surface)
                        .labelStyle(.titleOnly).menuStyle(.button).menuIndicator(.hidden).fixedSize()
                }
            }
            .buttonStyle(.ghost).textStyle(.callout).controlSize(.small)
        }
    }
}

/// Move to…: the places a fact may be filed under, but the one it is filed to. A row's menu holds it as a submenu.
struct MoveToMenu: View {
    let items: [Item]
    let surface: MarkSurface
    @Environment(FactHomes.self) private var homes: FactHomes?

    var body: some View {
        if let homes {
            let ids = items.compactMap(\.id)
            Menu("Move to…", systemImage: "folder") {
                ForEach(homes.destinations(for: ids)) { place in
                    Button(place.name, systemImage: place.symbol) { homes.move(ids, to: place.id, surface: surface) }
                }
            }
            .disabled(ids.isEmpty)
        }
    }
}

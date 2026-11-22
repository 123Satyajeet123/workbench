import AppKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "theme"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> AppTheme {
        defaults.string(forKey: key).flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    func apply() { NSApp.appearance = appearance }
}

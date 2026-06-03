import Foundation

/// Whether the left/right click behaviors on the menu bar status item are swapped.
///
/// - `.standard`: primary click (left) opens the dashboard (component panel);
///   secondary click (right or Control-click) opens the feature panel.
/// - `.swapped`: primary click opens the feature panel; secondary click opens
///   the dashboard.
enum MenuBarClickBehaviorPreference: String, CaseIterable, Identifiable {
    case standard
    case swapped

    static let userDefaultsKey = "menuBar.clickBehaviorPreference"

    var id: String { rawValue }

    var isSwapped: Bool { self == .swapped }

    var title: String {
        switch self {
        case .standard:
            return "默认"
        case .swapped:
            return "互换"
        }
    }

    /// Reads the current preference from `UserDefaults` (defaults to `.standard`).
    static func current(_ userDefaults: UserDefaults = .standard) -> MenuBarClickBehaviorPreference {
        userDefaults.string(forKey: userDefaultsKey)
            .flatMap(MenuBarClickBehaviorPreference.init(rawValue:))
            ?? .standard
    }
}

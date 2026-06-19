import Foundation

/// Whether the primary/secondary click behaviors on the menu bar status item are swapped.
///
/// - `.standard`: primary click (left) opens the dashboard (component panel);
///   secondary click opens the feature panel. Option+left-click is supported
///   on every macOS version; macOS 14...26 also keep native right-click and
///   Control-click when AppKit routes them.
/// - `.swapped`: primary click opens the feature panel; secondary click opens
///   the dashboard.
enum MenuBarClickBehaviorPreference: String {
    case standard
    case swapped

    static let userDefaultsKey = "menuBar.clickBehaviorPreference"

    var isSwapped: Bool { self == .swapped }

    /// Reads the current preference from `UserDefaults` (defaults to `.standard`).
    static func current(_ userDefaults: UserDefaults = .standard) -> MenuBarClickBehaviorPreference {
        userDefaults.string(forKey: userDefaultsKey)
            .flatMap(MenuBarClickBehaviorPreference.init(rawValue:))
            ?? .standard
    }
}

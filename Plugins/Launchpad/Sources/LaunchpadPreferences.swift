import Combine
import MacToolsPluginKit

/// User-tunable launcher settings, persisted in the plugin's scoped `PluginStorage`
/// (survives relaunch). Owned by the plugin and shared with the overlay + settings view.
@MainActor
final class LaunchpadPreferences: ObservableObject {
    enum WindowMode: String, CaseIterable, Identifiable {
        case fullscreen
        case compact

        var id: String { rawValue }

        func label(localization: PluginLocalization) -> String {
            switch self {
            case .fullscreen:
                localization.string("windowMode.fullscreen", defaultValue: "全屏")
            case .compact:
                localization.string("windowMode.compact", defaultValue: "紧凑窗口")
            }
        }
    }

    /// Screen corner that summons the launcher when the cursor dwells there. `off` = none.
    enum HotCorner: String, CaseIterable, Identifiable {
        case off
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var id: String { rawValue }

        func label(localization: PluginLocalization) -> String {
            switch self {
            case .off:
                localization.string("hotCorner.off", defaultValue: "关闭")
            case .topLeft:
                localization.string("hotCorner.topLeft", defaultValue: "左上")
            case .topRight:
                localization.string("hotCorner.topRight", defaultValue: "右上")
            case .bottomLeft:
                localization.string("hotCorner.bottomLeft", defaultValue: "左下")
            case .bottomRight:
                localization.string("hotCorner.bottomRight", defaultValue: "右下")
            }
        }
    }

    /// `columns == autoColumns` means "fit to width"; otherwise a fixed count.
    static let autoColumns = 0
    static let minColumns = 4
    static let maxColumns = 12

    @Published var windowMode: WindowMode {
        didSet { storage.set(windowMode.rawValue, forKey: Keys.windowMode) }
    }

    @Published var columns: Int {
        didSet {
            // Clamp on the single write path so no out-of-range value is ever persisted,
            // even from a programmatic set (Codex P2). Re-entry settles after one pass.
            let valid = Self.normalizedColumns(columns)
            guard valid == columns else { columns = valid; return }
            storage.set(columns, forKey: Keys.columns)
        }
    }

    /// App ids (resolved absolute paths) the user has hidden from the grid.
    @Published private(set) var hiddenAppIDs: Set<String> {
        didSet { storage.set(Array(hiddenAppIDs), forKey: Keys.hidden) }
    }

    func hide(_ id: String) { hiddenAppIDs.insert(id) }
    func unhide(_ id: String) { hiddenAppIDs.remove(id) }
    func unhideAll() { hiddenAppIDs.removeAll() }

    @Published var hotCorner: HotCorner {
        didSet { storage.set(hotCorner.rawValue, forKey: Keys.hotCorner) }
    }

    // MARK: Glass background (design §5)

    @Published var backgroundStyle: LaunchpadBackgroundStyle {
        didSet { storage.set(backgroundStyle.rawValue, forKey: Keys.backgroundStyle) }
    }

    /// Only consulted while `backgroundStyle == .custom`; kept persisted across style
    /// switches so flipping back to custom restores the user's last tuning.
    @Published var backgroundMaterial: LaunchpadGlassMaterial {
        didSet { storage.set(backgroundMaterial.rawValue, forKey: Keys.backgroundMaterial) }
    }

    /// Custom-style dim layer, in whole percent (PluginStorage has no double accessor).
    @Published var backgroundDimPercent: Int {
        didSet {
            // Same single-write-path clamp discipline as `columns`.
            let valid = LaunchpadBackgroundDim.normalized(backgroundDimPercent)
            guard valid == backgroundDimPercent else { backgroundDimPercent = valid; return }
            storage.set(backgroundDimPercent, forKey: Keys.backgroundDimPercent)
        }
    }

    /// The full rendering description. The overlay snapshots it at `open()` (same session
    /// discipline as `windowMode`) — settings changes apply on the next summon.
    var backgroundRecipe: LaunchpadBackgroundRecipe {
        backgroundStyle.recipe(
            customMaterial: backgroundMaterial,
            customDimPercent: backgroundDimPercent
        )
    }

    private let storage: PluginStorage

    private enum Keys {
        static let windowMode = "windowMode"
        static let columns = "columns"
        static let hidden = "hiddenAppIDs"
        static let hotCorner = "hotCorner"
        static let backgroundStyle = "backgroundStyle"
        static let backgroundMaterial = "backgroundMaterial"
        static let backgroundDimPercent = "backgroundDimPercent"
    }

    static func normalizedColumns(_ value: Int) -> Int {
        value == autoColumns ? autoColumns : min(max(value, minColumns), maxColumns)
    }

    init(storage: PluginStorage) {
        self.storage = storage
        self.windowMode = WindowMode(rawValue: storage.string(forKey: Keys.windowMode) ?? "")
            ?? .fullscreen
        // `integer(forKey:)` is 0 when unset → autoColumns, our default.
        self.columns = Self.normalizedColumns(storage.integer(forKey: Keys.columns))
        self.hiddenAppIDs = Set(storage.stringArray(forKey: Keys.hidden) ?? [])
        self.hotCorner = HotCorner(rawValue: storage.string(forKey: Keys.hotCorner) ?? "") ?? .off
        // Unknown raw values (a downgrade wrote a future style) fall back to the default,
        // same pattern as `windowMode`.
        self.backgroundStyle = LaunchpadBackgroundStyle(
            rawValue: storage.string(forKey: Keys.backgroundStyle) ?? ""
        ) ?? .standard
        self.backgroundMaterial = LaunchpadGlassMaterial(
            rawValue: storage.string(forKey: Keys.backgroundMaterial) ?? ""
        ) ?? .launchpad
        // `integer(forKey:)` returns 0 when unset, but 0 is a VALID dim — probe with
        // `object(forKey:)` so a stored 0 isn't mistaken for "use the default".
        self.backgroundDimPercent = storage.object(forKey: Keys.backgroundDimPercent) == nil
            ? LaunchpadBackgroundDim.defaultPercent
            : LaunchpadBackgroundDim.normalized(storage.integer(forKey: Keys.backgroundDimPercent))
    }
}

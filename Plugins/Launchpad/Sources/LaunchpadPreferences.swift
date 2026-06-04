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
        var label: String { self == .fullscreen ? "全屏" : "紧凑窗口" }
    }

    /// Screen corner that summons the launcher when the cursor dwells there. `off` = none.
    enum HotCorner: String, CaseIterable, Identifiable {
        case off
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var id: String { rawValue }
        var label: String {
            switch self {
            case .off: return "关闭"
            case .topLeft: return "左上"
            case .topRight: return "右上"
            case .bottomLeft: return "左下"
            case .bottomRight: return "右下"
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

    private let storage: PluginStorage

    private enum Keys {
        static let windowMode = "windowMode"
        static let columns = "columns"
        static let hidden = "hiddenAppIDs"
        static let hotCorner = "hotCorner"
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
    }
}

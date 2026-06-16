import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import LaunchpadPlugin

@MainActor
final class LaunchpadPreferencesTests: XCTestCase {

    // Uses the shared `FakePluginStorage` fixture (Tests/FakePluginStorage.swift).

    func testDefaultsWhenStorageEmpty() {
        let prefs = LaunchpadPreferences(storage: FakePluginStorage())
        XCTAssertEqual(prefs.windowMode, .fullscreen)
        XCTAssertEqual(prefs.columns, LaunchpadPreferences.autoColumns)
    }

    func testLoadsPersistedValues() {
        let store = FakePluginStorage()
        store.values["windowMode"] = "compact"
        store.values["columns"] = 6
        let prefs = LaunchpadPreferences(storage: store)
        XCTAssertEqual(prefs.windowMode, .compact)
        XCTAssertEqual(prefs.columns, 6)
    }

    func testInvalidStoredColumnsClampedOnLoad() {
        let store = FakePluginStorage()
        store.values["columns"] = 99            // out of 4...12 range
        XCTAssertEqual(LaunchpadPreferences(storage: store).columns, LaunchpadPreferences.maxColumns)
    }

    func testWindowModeWriteThrough() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.windowMode = .compact
        XCTAssertEqual(store.values["windowMode"] as? String, "compact")
    }

    func testColumnsClampOnWritePersistsValidValue() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.columns = 99                       // programmatic out-of-range set
        XCTAssertEqual(prefs.columns, LaunchpadPreferences.maxColumns)
        XCTAssertEqual(store.values["columns"] as? Int, LaunchpadPreferences.maxColumns)

        prefs.columns = 1                        // below min
        XCTAssertEqual(prefs.columns, LaunchpadPreferences.minColumns)
    }

    func testAutoColumnsPreservedOnWrite() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.columns = LaunchpadPreferences.autoColumns
        XCTAssertEqual(prefs.columns, LaunchpadPreferences.autoColumns)
        XCTAssertEqual(store.values["columns"] as? Int, LaunchpadPreferences.autoColumns)
    }

    func testNormalizedColumns() {
        XCTAssertEqual(LaunchpadPreferences.normalizedColumns(0), 0)       // auto sentinel
        XCTAssertEqual(LaunchpadPreferences.normalizedColumns(8), 8)
        XCTAssertEqual(LaunchpadPreferences.normalizedColumns(2), LaunchpadPreferences.minColumns)
        XCTAssertEqual(LaunchpadPreferences.normalizedColumns(50), LaunchpadPreferences.maxColumns)
    }

    func testHideUnhidePersists() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.hide("/Applications/A.app")
        prefs.hide("/Applications/B.app")
        XCTAssertEqual(prefs.hiddenAppIDs, ["/Applications/A.app", "/Applications/B.app"])
        XCTAssertEqual(Set(store.values["hiddenAppIDs"] as? [String] ?? []), prefs.hiddenAppIDs)

        prefs.unhide("/Applications/A.app")
        XCTAssertEqual(prefs.hiddenAppIDs, ["/Applications/B.app"])
        XCTAssertEqual(store.values["hiddenAppIDs"] as? [String], ["/Applications/B.app"])
    }

    func testHiddenLoadedFromStorage() {
        let store = FakePluginStorage()
        store.values["hiddenAppIDs"] = ["/Applications/X.app", "/Applications/Y.app"]
        let prefs = LaunchpadPreferences(storage: store)
        XCTAssertEqual(prefs.hiddenAppIDs, ["/Applications/X.app", "/Applications/Y.app"])
    }

    func testUnhideAll() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.hide("/Applications/A.app")
        prefs.hide("/Applications/B.app")
        prefs.unhideAll()
        XCTAssertTrue(prefs.hiddenAppIDs.isEmpty)
        XCTAssertEqual(store.values["hiddenAppIDs"] as? [String], [])
    }

    // MARK: - Appearance keys (design §3.1, P2)

    func testAppearanceDefaultsWhenStorageEmpty() {
        let prefs = LaunchpadPreferences(storage: FakePluginStorage())
        XCTAssertEqual(prefs.iconSize, 64, "未设值 → 默认 64pt")
        XCTAssertFalse(prefs.hidesAppNames, "取反键：未设值 = false = 显示名字（零迁移）")
        XCTAssertEqual(prefs.compactScalePercent, 72, "未设值 → 默认 72%")
    }

    func testAppearanceRoundTrip() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.iconSize = 96
        prefs.hidesAppNames = true
        prefs.compactScalePercent = 55
        XCTAssertEqual(store.values["iconSize"] as? Int, 96)
        XCTAssertEqual(store.values["hidesAppNames"] as? Bool, true)
        XCTAssertEqual(store.values["compactScalePercent"] as? Int, 55)

        // A fresh instance over the same storage reads the values back.
        let reloaded = LaunchpadPreferences(storage: store)
        XCTAssertEqual(reloaded.iconSize, 96)
        XCTAssertTrue(reloaded.hidesAppNames)
        XCTAssertEqual(reloaded.compactScalePercent, 55)
    }

    func testIconSizeClampAndStepOnWritePersistValidValue() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.iconSize = 999                      // way above max
        XCTAssertEqual(prefs.iconSize, 96)
        XCTAssertEqual(store.values["iconSize"] as? Int, 96)

        prefs.iconSize = 30                       // below min
        XCTAssertEqual(prefs.iconSize, 48)

        prefs.iconSize = 50                       // off-step → snapped to the 4pt grid
        XCTAssertEqual(prefs.iconSize, 52)
        XCTAssertEqual(store.values["iconSize"] as? Int, 52)
    }

    func testInvalidStoredAppearanceValuesNormalizedOnLoad() {
        let store = FakePluginStorage()
        store.values["iconSize"] = 47             // hand-edited: off-step + below min
        store.values["compactScalePercent"] = 99  // above max
        let prefs = LaunchpadPreferences(storage: store)
        XCTAssertEqual(prefs.iconSize, 48)
        XCTAssertEqual(prefs.compactScalePercent, 90)
    }

    func testCompactScaleClampOnWrite() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.compactScalePercent = 10
        XCTAssertEqual(prefs.compactScalePercent, 55)
        XCTAssertEqual(store.values["compactScalePercent"] as? Int, 55)
        prefs.compactScalePercent = 100
        XCTAssertEqual(prefs.compactScalePercent, 90)
    }

    func testNormalizedIconSize() {
        XCTAssertEqual(LaunchpadPreferences.normalizedIconSize(0), 64, "0 哨兵 → 默认")
        XCTAssertEqual(LaunchpadPreferences.normalizedIconSize(47), 48)
        XCTAssertEqual(LaunchpadPreferences.normalizedIconSize(97), 96)
        XCTAssertEqual(LaunchpadPreferences.normalizedIconSize(64), 64)
        XCTAssertEqual(LaunchpadPreferences.normalizedIconSize(50), 52, "步进对齐：四舍五入到 4 的倍数")
        XCTAssertEqual(LaunchpadPreferences.normalizedIconSize(49), 48)
        // Every value already on the step survives unchanged.
        for v in stride(from: 48, through: 96, by: 4) {
            XCTAssertEqual(LaunchpadPreferences.normalizedIconSize(v), v)
        }
    }

    func testNormalizedCompactScale() {
        XCTAssertEqual(LaunchpadPreferences.normalizedCompactScale(0), 72, "0 哨兵 → 默认")
        XCTAssertEqual(LaunchpadPreferences.normalizedCompactScale(54), 55)
        XCTAssertEqual(LaunchpadPreferences.normalizedCompactScale(91), 90)
        XCTAssertEqual(LaunchpadPreferences.normalizedCompactScale(72), 72)
    }

    /// `appearance` is the single read-only projection `resolve(_:)` consumes.
    func testAppearanceDerivation() {
        let prefs = LaunchpadPreferences(storage: FakePluginStorage())
        XCTAssertEqual(prefs.appearance, LaunchpadAppearance(iconSide: 64, showsLabels: true),
                       "默认派生 = 历史外观（byte-compat 锚点的输入端）")

        prefs.iconSize = 80
        prefs.hidesAppNames = true
        XCTAssertEqual(prefs.appearance, LaunchpadAppearance(iconSide: 80, showsLabels: false),
                       "showsLabels = !hidesAppNames，iconSide 跟随 iconSize")
    }

    // MARK: - Label-style keys (design 2026-06-13)

    func testLabelStyleDefaultsWhenStorageEmpty() {
        let prefs = LaunchpadPreferences(storage: FakePluginStorage())
        XCTAssertEqual(prefs.labelColor, .automatic, "未设值 → .automatic（零迁移）")
        XCTAssertEqual(prefs.labelWeight, .regular, "未设值 → .regular")
        XCTAssertEqual(prefs.labelSize, .medium, "未设值 → .medium（历史 12pt 基线）")
    }

    func testLabelStyleRoundTrip() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.labelColor = .accent
        prefs.labelWeight = .bold
        prefs.labelSize = .large
        XCTAssertEqual(store.values["labelColor"] as? String, "accent")
        XCTAssertEqual(store.values["labelWeight"] as? String, "bold")
        XCTAssertEqual(store.values["labelSize"] as? String, "large")

        // A fresh instance over the same storage reads the raw values back.
        let reloaded = LaunchpadPreferences(storage: store)
        XCTAssertEqual(reloaded.labelColor, .accent)
        XCTAssertEqual(reloaded.labelWeight, .bold)
        XCTAssertEqual(reloaded.labelSize, .large)
    }

    func testUnknownStoredLabelValuesFallBackToDefaults() {
        let store = FakePluginStorage()
        store.values["labelColor"] = "neon"        // a future/garbage raw value
        store.values["labelWeight"] = "ultralight"
        store.values["labelSize"] = "huge"
        let prefs = LaunchpadPreferences(storage: store)
        XCTAssertEqual(prefs.labelColor, .automatic, "未知颜色值降级回 .automatic")
        XCTAssertEqual(prefs.labelWeight, .regular, "未知字重值降级回 .regular")
        XCTAssertEqual(prefs.labelSize, .medium, "未知字号值降级回 .medium")
    }

    func testAppearanceDerivationCarriesLabelStyle() {
        let prefs = LaunchpadPreferences(storage: FakePluginStorage())
        prefs.labelColor = .light
        prefs.labelWeight = .semibold
        prefs.labelSize = .small
        XCTAssertEqual(prefs.appearance,
                       LaunchpadAppearance(iconSide: 64, showsLabels: true,
                                           labelColor: .light, labelWeight: .semibold, labelSize: .small),
                       "appearance 投影必须携带三个标签样式字段")
    }
}

import AppKit
import XCTest
@testable import MacTools
@testable import LaunchpadPlugin

/// Glass-background model + persistence (design §5.7): preset → recipe resolution,
/// custom passthrough, dim clamping on the single write path, decode fallbacks,
/// storage round-trip and the NSMaterial mapping completeness.
@MainActor
final class LaunchpadBackgroundStyleTests: XCTestCase {

    // MARK: - Preset → recipe resolution (pure function)

    /// G1 regression anchor: the default style resolves to the pre-change rendering path —
    /// an untouched preference must stay pixel-identical, independent of the custom knobs.
    func testStandardPresetResolvesToLegacyAnchor() {
        XCTAssertEqual(
            LaunchpadBackgroundStyle.standard.recipe(customMaterial: .hud, customDimPercent: 60),
            .legacyUltraThin
        )
    }

    func testClearPresetRecipe() {
        XCTAssertEqual(
            LaunchpadBackgroundStyle.clear.recipe(customMaterial: .hud, customDimPercent: 60),
            .glass(material: .launchpad, dimOpacity: 0, forcesDarkAppearance: false)
        )
    }

    func testDeepPresetRecipe() {
        XCTAssertEqual(
            LaunchpadBackgroundStyle.deep.recipe(customMaterial: .subtle, customDimPercent: 0),
            .glass(material: .hud, dimOpacity: 0.28, forcesDarkAppearance: true)
        )
    }

    /// Only the custom style consumes the custom knobs; it never forces dark (G3 — the
    /// deep preset owns forced-dark, no separate toggle).
    func testCustomRecipePassesThroughMaterialAndDim() {
        XCTAssertEqual(
            LaunchpadBackgroundStyle.custom.recipe(customMaterial: .frosted, customDimPercent: 35),
            .glass(material: .frosted, dimOpacity: 0.35, forcesDarkAppearance: false)
        )
    }

    func testCustomRecipeClampsOutOfRangeDim() {
        XCTAssertEqual(
            LaunchpadBackgroundStyle.custom.recipe(customMaterial: .subtle, customDimPercent: 999),
            .glass(material: .subtle, dimOpacity: 0.60, forcesDarkAppearance: false)
        )
        XCTAssertEqual(
            LaunchpadBackgroundStyle.custom.recipe(customMaterial: .subtle, customDimPercent: -10),
            .glass(material: .subtle, dimOpacity: 0, forcesDarkAppearance: false)
        )
    }

    func testNormalizedDim() {
        XCTAssertEqual(LaunchpadBackgroundDim.normalized(-10), 0)
        XCTAssertEqual(LaunchpadBackgroundDim.normalized(0), 0)
        XCTAssertEqual(LaunchpadBackgroundDim.normalized(35), 35)
        XCTAssertEqual(LaunchpadBackgroundDim.normalized(999), 60)
    }

    // MARK: - Preferences: defaults, fallbacks, clamping, round-trip

    func testBackgroundDefaultsWhenStorageEmpty() {
        let prefs = LaunchpadPreferences(storage: FakePluginStorage())
        XCTAssertEqual(prefs.backgroundStyle, .standard)
        XCTAssertEqual(prefs.backgroundMaterial, .launchpad)
        XCTAssertEqual(prefs.backgroundDimPercent, LaunchpadBackgroundDim.defaultPercent)
        // The derived recipe of a fresh install IS the status-quo rendering.
        XCTAssertEqual(prefs.backgroundRecipe, .legacyUltraThin)
    }

    /// Unknown raw values (e.g. written by a future version) fall back to the defaults,
    /// mirroring the `windowMode` decode pattern.
    func testUnknownRawValuesFallBackToDefaults() {
        let store = FakePluginStorage()
        store.values["backgroundStyle"] = "neon"
        store.values["backgroundMaterial"] = "mirror"
        let prefs = LaunchpadPreferences(storage: store)
        XCTAssertEqual(prefs.backgroundStyle, .standard)
        XCTAssertEqual(prefs.backgroundMaterial, .launchpad)
    }

    /// `integer(forKey:)` returns 0 when unset, but 0 is a valid dim — a persisted 0 must
    /// load as 0 (not the 12 default), and only a truly absent key uses the default.
    func testPersistedZeroDimIsNotTreatedAsUnset() {
        let store = FakePluginStorage()
        store.values["backgroundDimPercent"] = 0
        XCTAssertEqual(LaunchpadPreferences(storage: store).backgroundDimPercent, 0)
    }

    func testOutOfRangeStoredDimClampedOnLoad() {
        let store = FakePluginStorage()
        store.values["backgroundDimPercent"] = 999
        XCTAssertEqual(LaunchpadPreferences(storage: store).backgroundDimPercent, 60)
    }

    /// Programmatic out-of-range sets settle through the single `didSet` write path and
    /// never persist an invalid value (same discipline as `columns`).
    func testDimClampOnWritePersistsValidValue() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.backgroundDimPercent = 999
        XCTAssertEqual(prefs.backgroundDimPercent, 60)
        XCTAssertEqual(store.values["backgroundDimPercent"] as? Int, 60)

        prefs.backgroundDimPercent = -10
        XCTAssertEqual(prefs.backgroundDimPercent, 0)
        XCTAssertEqual(store.values["backgroundDimPercent"] as? Int, 0)
    }

    func testBackgroundRoundTrip() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.backgroundStyle = .custom
        prefs.backgroundMaterial = .hud
        prefs.backgroundDimPercent = 45

        let reloaded = LaunchpadPreferences(storage: store)
        XCTAssertEqual(reloaded.backgroundStyle, .custom)
        XCTAssertEqual(reloaded.backgroundMaterial, .hud)
        XCTAssertEqual(reloaded.backgroundDimPercent, 45)
        XCTAssertEqual(
            reloaded.backgroundRecipe,
            .glass(material: .hud, dimOpacity: 0.45, forcesDarkAppearance: false)
        )
    }

    /// Switching presets leaves the custom knobs persisted, so flipping back to custom
    /// restores the user's last tuning.
    func testPresetSwitchPreservesCustomKnobs() {
        let store = FakePluginStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.backgroundStyle = .custom
        prefs.backgroundMaterial = .frosted
        prefs.backgroundDimPercent = 30
        prefs.backgroundStyle = .deep
        XCTAssertEqual(prefs.backgroundRecipe, .glass(material: .hud, dimOpacity: 0.28, forcesDarkAppearance: true))
        prefs.backgroundStyle = .custom
        XCTAssertEqual(prefs.backgroundRecipe, .glass(material: .frosted, dimOpacity: 0.30, forcesDarkAppearance: false))
    }

    // MARK: - View-layer material mapping

    /// Whitelist completeness: every model material maps to a distinct AppKit material,
    /// and the mapping stays inside the design's whitelist (no near-opaque chrome).
    func testNSMaterialMappingCoversAllCasesDistinctly() {
        let expected: [LaunchpadGlassMaterial: NSVisualEffectView.Material] = [
            .launchpad: .fullScreenUI,
            .frosted: .popover,
            .hud: .hudWindow,
            .subtle: .underWindowBackground,
        ]
        XCTAssertEqual(Set(LaunchpadGlassMaterial.allCases), Set(expected.keys))
        for material in LaunchpadGlassMaterial.allCases {
            XCTAssertEqual(material.nsMaterial, expected[material])
        }
        XCTAssertEqual(Set(LaunchpadGlassMaterial.allCases.map(\.nsMaterial)).count,
                       LaunchpadGlassMaterial.allCases.count)
    }
}

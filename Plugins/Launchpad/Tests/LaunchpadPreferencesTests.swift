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
}

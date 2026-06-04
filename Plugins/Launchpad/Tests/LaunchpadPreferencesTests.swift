import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import LaunchpadPlugin

@MainActor
final class LaunchpadPreferencesTests: XCTestCase {

    /// In-memory `PluginStorage` so tests touch no real UserDefaults.
    @MainActor
    private final class FakeStorage: PluginStorage {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func data(forKey key: String) -> Data? { values[key] as? Data }
        func string(forKey key: String) -> String? { values[key] as? String }
        func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
        func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values[key] = nil }
        func migrateValueIfNeeded(fromLegacyKey legacyKey: String, to key: String) {
            if values[key] == nil, let legacy = values[legacyKey] {
                values[key] = legacy
                values[legacyKey] = nil
            }
        }
    }

    func testDefaultsWhenStorageEmpty() {
        let prefs = LaunchpadPreferences(storage: FakeStorage())
        XCTAssertEqual(prefs.windowMode, .fullscreen)
        XCTAssertEqual(prefs.columns, LaunchpadPreferences.autoColumns)
    }

    func testLoadsPersistedValues() {
        let store = FakeStorage()
        store.values["windowMode"] = "compact"
        store.values["columns"] = 6
        let prefs = LaunchpadPreferences(storage: store)
        XCTAssertEqual(prefs.windowMode, .compact)
        XCTAssertEqual(prefs.columns, 6)
    }

    func testInvalidStoredColumnsClampedOnLoad() {
        let store = FakeStorage()
        store.values["columns"] = 99            // out of 4...12 range
        XCTAssertEqual(LaunchpadPreferences(storage: store).columns, LaunchpadPreferences.maxColumns)
    }

    func testWindowModeWriteThrough() {
        let store = FakeStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.windowMode = .compact
        XCTAssertEqual(store.values["windowMode"] as? String, "compact")
    }

    func testColumnsClampOnWritePersistsValidValue() {
        let store = FakeStorage()
        let prefs = LaunchpadPreferences(storage: store)
        prefs.columns = 99                       // programmatic out-of-range set
        XCTAssertEqual(prefs.columns, LaunchpadPreferences.maxColumns)
        XCTAssertEqual(store.values["columns"] as? Int, LaunchpadPreferences.maxColumns)

        prefs.columns = 1                        // below min
        XCTAssertEqual(prefs.columns, LaunchpadPreferences.minColumns)
    }

    func testAutoColumnsPreservedOnWrite() {
        let store = FakeStorage()
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
}

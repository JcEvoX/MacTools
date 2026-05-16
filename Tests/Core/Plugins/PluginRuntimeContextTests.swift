import XCTest
@testable import MacTools

@MainActor
final class PluginRuntimeContextTests: XCTestCase {
    private let suiteName = "PluginRuntimeContextTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testStorageScopesKeysByPluginID() {
        let defaults = isolatedDefaults()
        let first = UserDefaultsPluginStorage(pluginID: "first", userDefaults: defaults)
        let second = UserDefaultsPluginStorage(pluginID: "second", userDefaults: defaults)

        first.set(true, forKey: "enabled")
        second.set(false, forKey: "enabled")

        XCTAssertTrue(first.bool(forKey: "enabled"))
        XCTAssertFalse(second.bool(forKey: "enabled"))
        XCTAssertEqual(defaults.object(forKey: "plugin.first.enabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "plugin.second.enabled") as? Bool, false)
    }

    func testStorageMigratesLegacyValueIntoScopedKeyOnce() {
        let defaults = isolatedDefaults()
        defaults.set(["item-a"], forKey: "launch-control.favorite-item-ids")
        defaults.set(["item-b"], forKey: "plugin.launch-control.launch-control.favorite-item-ids")
        let storage = UserDefaultsPluginStorage(pluginID: "launch-control", userDefaults: defaults)

        storage.migrateValueIfNeeded(
            fromLegacyKey: "launch-control.favorite-item-ids",
            to: "launch-control.favorite-item-ids"
        )

        XCTAssertEqual(storage.stringArray(forKey: "launch-control.favorite-item-ids"), ["item-b"])
        XCTAssertEqual(defaults.stringArray(forKey: "launch-control.favorite-item-ids"), ["item-a"])
    }

    func testStorageMigratesLegacyValueAndRemovesLegacyKeyWhenScopedValueIsMissing() {
        let defaults = isolatedDefaults()
        defaults.set(4, forKey: "middle-click.required-finger-count")
        let storage = UserDefaultsPluginStorage(pluginID: "middle-click", userDefaults: defaults)

        storage.migrateValueIfNeeded(
            fromLegacyKey: "middle-click.required-finger-count",
            to: "middle-click.required-finger-count"
        )

        XCTAssertEqual(storage.integer(forKey: "middle-click.required-finger-count"), 4)
        XCTAssertNil(defaults.object(forKey: "middle-click.required-finger-count"))
    }

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

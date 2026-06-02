import XCTest
import MacToolsPluginKit
@testable import MenuBarHiddenPlugin

@MainActor
final class MenuBarHiddenStoreTests: XCTestCase {

    func testEnabledDefaultsToFalse() {
        let store = MenuBarHiddenStore(storage: MenuBarHiddenMemoryStorage())
        XCTAssertFalse(store.isEnabled)
    }

    func testAlwaysHiddenItemStableKeysDefaultToEmpty() {
        let store = MenuBarHiddenStore(storage: MenuBarHiddenMemoryStorage())

        XCTAssertTrue(store.alwaysHiddenItemStableKeys.isEmpty)
    }

    func testAlwaysHiddenItemStableKeysPersistSortedWithoutDuplicates() {
        let storage = MenuBarHiddenMemoryStorage()
        let store = MenuBarHiddenStore(storage: storage)
        let first = MenuBarItemTag(namespace: "com.example.b", title: "Item", windowID: nil, instanceIndex: 0)
        let second = MenuBarItemTag(namespace: "com.example.a", title: "Item", windowID: nil, instanceIndex: 1)

        store.recordAlwaysHiddenItem(first)
        store.recordAlwaysHiddenItem(second)
        store.recordAlwaysHiddenItem(first)

        XCTAssertEqual(storage.stringArray(forKey: "always-hidden-item-stable-keys"), [
            "com.example.a:Item:1",
            "com.example.b:Item",
        ])
        XCTAssertEqual(MenuBarHiddenStore(storage: storage).alwaysHiddenItemStableKeys, [
            "com.example.a:Item:1",
            "com.example.b:Item",
        ])
    }

    func testRemovingLastAlwaysHiddenItemClearsStorage() {
        let storage = MenuBarHiddenMemoryStorage()
        let store = MenuBarHiddenStore(storage: storage)
        let tag = MenuBarItemTag(namespace: "com.example.app", title: "Item", windowID: nil, instanceIndex: 0)

        store.recordAlwaysHiddenItem(tag)
        store.removeAlwaysHiddenItem(tag)

        XCTAssertTrue(store.alwaysHiddenItemStableKeys.isEmpty)
        XCTAssertNil(storage.stringArray(forKey: "always-hidden-item-stable-keys"))
    }
}

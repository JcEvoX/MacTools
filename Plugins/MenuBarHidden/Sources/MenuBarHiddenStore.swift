import Foundation
import MacToolsPluginKit

@MainActor
final class MenuBarHiddenStore {
    private enum Key {
        static let isEnabled = "is-enabled"
        static let isAlwaysHiddenEnabled = "is-always-hidden-enabled"
        static let showsHiddenIconsInPanel = "shows-hidden-icons-in-panel"
        static let alwaysHiddenItemStableKeys = "always-hidden-item-stable-keys"
    }

    private let storage: PluginStorage

    init(storage: PluginStorage) {
        self.storage = storage
    }

    var isEnabled: Bool {
        get { storage.object(forKey: Key.isEnabled) as? Bool ?? false }
        set { storage.set(newValue, forKey: Key.isEnabled) }
    }

    var isAlwaysHiddenEnabled: Bool {
        get { storage.object(forKey: Key.isAlwaysHiddenEnabled) as? Bool ?? false }
        set { storage.set(newValue, forKey: Key.isAlwaysHiddenEnabled) }
    }

    var showsHiddenIconsInPanel: Bool {
        get { storage.object(forKey: Key.showsHiddenIconsInPanel) as? Bool ?? false }
        set { storage.set(newValue, forKey: Key.showsHiddenIconsInPanel) }
    }

    var alwaysHiddenItemStableKeys: Set<String> {
        get {
            Set(storage.stringArray(forKey: Key.alwaysHiddenItemStableKeys) ?? [])
        }
        set {
            let keys = newValue.sorted()
            if keys.isEmpty {
                storage.removeObject(forKey: Key.alwaysHiddenItemStableKeys)
            } else {
                storage.set(keys, forKey: Key.alwaysHiddenItemStableKeys)
            }
        }
    }

    func recordAlwaysHiddenItem(_ tag: MenuBarItemTag) {
        var keys = alwaysHiddenItemStableKeys
        guard keys.insert(tag.stableKey).inserted else { return }
        alwaysHiddenItemStableKeys = keys
    }

    func removeAlwaysHiddenItem(_ tag: MenuBarItemTag) {
        var keys = alwaysHiddenItemStableKeys
        guard keys.remove(tag.stableKey) != nil else { return }
        alwaysHiddenItemStableKeys = keys
    }
}

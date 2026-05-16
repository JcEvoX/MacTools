import Foundation

@MainActor
struct PluginRuntimeContext {
    let pluginID: String
    let resourceBundle: Bundle
    let resourceSubdirectory: String?
    let storage: PluginStorage

    init(
        pluginID: String,
        resourceBundle: Bundle = .main,
        resourceSubdirectory: String? = nil,
        storage: PluginStorage? = nil
    ) {
        self.pluginID = pluginID
        self.resourceBundle = resourceBundle
        self.resourceSubdirectory = resourceSubdirectory
        self.storage = storage ?? UserDefaultsPluginStorage(pluginID: pluginID)
    }

    func resourceURL(forResource name: String, withExtension ext: String?) -> URL? {
        if let resourceSubdirectory,
           let url = resourceBundle.url(
               forResource: name,
               withExtension: ext,
               subdirectory: resourceSubdirectory
           ) {
            return url
        }

        return resourceBundle.url(forResource: name, withExtension: ext)
    }
}

@MainActor
protocol PluginStorage {
    func object(forKey key: String) -> Any?
    func data(forKey key: String) -> Data?
    func string(forKey key: String) -> String?
    func stringArray(forKey key: String) -> [String]?
    func integer(forKey key: String) -> Int
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    func migrateValueIfNeeded(fromLegacyKey legacyKey: String, to key: String)
}

@MainActor
final class UserDefaultsPluginStorage: PluginStorage {
    private let pluginID: String
    private let userDefaults: UserDefaults

    init(pluginID: String, userDefaults: UserDefaults = .standard) {
        self.pluginID = pluginID
        self.userDefaults = userDefaults
    }

    func object(forKey key: String) -> Any? {
        userDefaults.object(forKey: storageKey(for: key))
    }

    func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: storageKey(for: key))
    }

    func string(forKey key: String) -> String? {
        userDefaults.string(forKey: storageKey(for: key))
    }

    func stringArray(forKey key: String) -> [String]? {
        userDefaults.stringArray(forKey: storageKey(for: key))
    }

    func integer(forKey key: String) -> Int {
        userDefaults.integer(forKey: storageKey(for: key))
    }

    func bool(forKey key: String) -> Bool {
        userDefaults.bool(forKey: storageKey(for: key))
    }

    func set(_ value: Any?, forKey key: String) {
        guard let value else {
            removeObject(forKey: key)
            return
        }

        userDefaults.set(value, forKey: storageKey(for: key))
    }

    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: storageKey(for: key))
    }

    func migrateValueIfNeeded(fromLegacyKey legacyKey: String, to key: String) {
        let scopedKey = storageKey(for: key)

        guard userDefaults.object(forKey: scopedKey) == nil,
              let legacyValue = userDefaults.object(forKey: legacyKey)
        else {
            return
        }

        userDefaults.set(legacyValue, forKey: scopedKey)
        userDefaults.removeObject(forKey: legacyKey)
    }

    private func storageKey(for key: String) -> String {
        "plugin.\(pluginID).\(key)"
    }
}

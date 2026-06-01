import Foundation
import MacToolsPluginKit

@MainActor
final class DeviceBatteryStore: ObservableObject {
    private enum Key {
        static let layoutMode = "layout-mode"
        static let showInternalBattery = "show-internal-battery"
        static let showBluetoothDevices = "show-bluetooth-devices"
        static let showRapooDevices = "show-rapoo-devices"
    }

    @Published private(set) var layoutMode: DeviceBatteryLayoutMode
    @Published private(set) var showInternalBattery: Bool
    @Published private(set) var showBluetoothDevices: Bool
    @Published private(set) var showRapooDevices: Bool

    private let storage: any PluginStorage

    init(storage: any PluginStorage) {
        self.storage = storage
        layoutMode = DeviceBatteryLayoutMode(
            rawValue: storage.string(forKey: Key.layoutMode) ?? DeviceBatteryLayoutMode.grid.rawValue
        ) ?? .grid
        showInternalBattery = Self.boolValue(storage, key: Key.showInternalBattery, defaultValue: true)
        showBluetoothDevices = Self.boolValue(storage, key: Key.showBluetoothDevices, defaultValue: true)
        showRapooDevices = Self.boolValue(storage, key: Key.showRapooDevices, defaultValue: true)
    }

    func setLayoutMode(_ mode: DeviceBatteryLayoutMode) {
        guard layoutMode != mode else {
            return
        }

        layoutMode = mode
        storage.set(mode.rawValue, forKey: Key.layoutMode)
    }

    func setShowInternalBattery(_ isShown: Bool) {
        guard showInternalBattery != isShown else {
            return
        }

        showInternalBattery = isShown
        storage.set(isShown, forKey: Key.showInternalBattery)
    }

    func setShowBluetoothDevices(_ isShown: Bool) {
        guard showBluetoothDevices != isShown else {
            return
        }

        showBluetoothDevices = isShown
        storage.set(isShown, forKey: Key.showBluetoothDevices)
    }

    func setShowRapooDevices(_ isShown: Bool) {
        guard showRapooDevices != isShown else {
            return
        }

        showRapooDevices = isShown
        storage.set(isShown, forKey: Key.showRapooDevices)
    }

    private static func boolValue(
        _ storage: any PluginStorage,
        key: String,
        defaultValue: Bool
    ) -> Bool {
        guard storage.object(forKey: key) != nil else {
            return defaultValue
        }

        return storage.bool(forKey: key)
    }
}


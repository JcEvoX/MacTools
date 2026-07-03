import Foundation
import MacToolsPluginKit

enum MouseScrollReverserDevice: Equatable, Sendable {
    case mouse
    case trackpad
}

struct MouseScrollReverserConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var reverseHorizontal: Bool
    var reverseVertical: Bool
    var reverseMouse: Bool
    var reverseTrackpad: Bool

    static let `default` = MouseScrollReverserConfiguration(
        isEnabled: false,
        reverseHorizontal: false,
        reverseVertical: true,
        reverseMouse: true,
        reverseTrackpad: false
    )

    var hasSelectedAxis: Bool {
        reverseHorizontal || reverseVertical
    }

    var hasSelectedDevice: Bool {
        reverseMouse || reverseTrackpad
    }

    var shouldInstallEventTap: Bool {
        isEnabled && hasSelectedAxis && hasSelectedDevice
    }

    func shouldReverse(device: MouseScrollReverserDevice) -> Bool {
        guard shouldInstallEventTap else {
            return false
        }

        switch device {
        case .mouse:
            return reverseMouse
        case .trackpad:
            return reverseTrackpad
        }
    }
}

@MainActor
final class MouseScrollReverserStore: ObservableObject {
    private enum StorageKey {
        static let isEnabled = "scroll-reverser.enabled"
        static let reverseHorizontal = "scroll-reverser.reverse-horizontal"
        static let reverseVertical = "scroll-reverser.reverse-vertical"
        static let reverseMouse = "scroll-reverser.reverse-mouse"
        static let reverseTrackpad = "scroll-reverser.reverse-trackpad"
    }

    @Published private(set) var configuration: MouseScrollReverserConfiguration

    private let storage: any PluginStorage

    init(storage: any PluginStorage) {
        self.storage = storage
        self.configuration = MouseScrollReverserConfiguration(
            isEnabled: Self.bool(
                forKey: StorageKey.isEnabled,
                defaultValue: MouseScrollReverserConfiguration.default.isEnabled,
                storage: storage
            ),
            reverseHorizontal: Self.bool(
                forKey: StorageKey.reverseHorizontal,
                defaultValue: MouseScrollReverserConfiguration.default.reverseHorizontal,
                storage: storage
            ),
            reverseVertical: Self.bool(
                forKey: StorageKey.reverseVertical,
                defaultValue: MouseScrollReverserConfiguration.default.reverseVertical,
                storage: storage
            ),
            reverseMouse: Self.bool(
                forKey: StorageKey.reverseMouse,
                defaultValue: MouseScrollReverserConfiguration.default.reverseMouse,
                storage: storage
            ),
            reverseTrackpad: Self.bool(
                forKey: StorageKey.reverseTrackpad,
                defaultValue: MouseScrollReverserConfiguration.default.reverseTrackpad,
                storage: storage
            )
        )
    }

    func setEnabled(_ isEnabled: Bool) {
        update(StorageKey.isEnabled, value: isEnabled) {
            $0.isEnabled = isEnabled
        }
    }

    func setReverseHorizontal(_ isEnabled: Bool) {
        update(StorageKey.reverseHorizontal, value: isEnabled) {
            $0.reverseHorizontal = isEnabled
        }
    }

    func setReverseVertical(_ isEnabled: Bool) {
        update(StorageKey.reverseVertical, value: isEnabled) {
            $0.reverseVertical = isEnabled
        }
    }

    func setReverseMouse(_ isEnabled: Bool) {
        update(StorageKey.reverseMouse, value: isEnabled) {
            $0.reverseMouse = isEnabled
        }
    }

    func setReverseTrackpad(_ isEnabled: Bool) {
        update(StorageKey.reverseTrackpad, value: isEnabled) {
            $0.reverseTrackpad = isEnabled
        }
    }

    private func update(
        _ key: String,
        value: Bool,
        mutate: (inout MouseScrollReverserConfiguration) -> Void
    ) {
        var next = configuration
        mutate(&next)
        guard next != configuration else {
            return
        }

        storage.set(value, forKey: key)
        configuration = next
    }

    private static func bool(
        forKey key: String,
        defaultValue: Bool,
        storage: any PluginStorage
    ) -> Bool {
        guard storage.object(forKey: key) != nil else {
            return defaultValue
        }

        return storage.bool(forKey: key)
    }
}


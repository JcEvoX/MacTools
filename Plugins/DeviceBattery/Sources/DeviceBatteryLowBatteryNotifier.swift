import Foundation
import MacToolsPluginKit
@preconcurrency import UserNotifications

struct DeviceBatteryLowBatteryNotification: Equatable {
    let title: String
    let body: String
    let deviceIDs: Set<String>
}

@MainActor
protocol DeviceBatteryLowBatteryNotifying {
    func notifyLowBatteryDevices(
        _ items: [DeviceBatteryItem],
        threshold: Int,
        localization: PluginLocalization
    )
}

@MainActor
final class DeviceBatteryLowBatteryNotificationController {
    private let notifier: any DeviceBatteryLowBatteryNotifying
    private var notifiedDeviceIDs: Set<String> = []

    init(notifier: any DeviceBatteryLowBatteryNotifying) {
        self.notifier = notifier
    }

    func evaluate(
        snapshot: DeviceBatterySnapshot,
        isEnabled: Bool,
        threshold: Int,
        localization: PluginLocalization
    ) {
        let normalizedThreshold = DeviceBatteryLowBatteryThresholds.normalized(threshold)
        guard isEnabled else {
            notifiedDeviceIDs.removeAll()
            return
        }

        let lowBatteryItems = snapshot.lowBatteryItems(threshold: normalizedThreshold)
        let lowBatteryDeviceIDs = Set(lowBatteryItems.map(\.id))
        notifiedDeviceIDs.formIntersection(lowBatteryDeviceIDs)

        let newLowBatteryItems = lowBatteryItems.filter { !notifiedDeviceIDs.contains($0.id) }
        guard !newLowBatteryItems.isEmpty else {
            return
        }

        notifier.notifyLowBatteryDevices(
            newLowBatteryItems,
            threshold: normalizedThreshold,
            localization: localization
        )
        notifiedDeviceIDs.formUnion(newLowBatteryItems.map(\.id))
    }
}

@MainActor
final class DeviceBatteryUserNotificationCenterNotifier: DeviceBatteryLowBatteryNotifying {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func notifyLowBatteryDevices(
        _ items: [DeviceBatteryItem],
        threshold: Int,
        localization: PluginLocalization
    ) {
        let notification = DeviceBatteryLowBatteryNotificationContent.make(
            items: items,
            threshold: threshold,
            localization: localization
        )

        let title = notification.title
        let body = notification.body
        let identifier = "device-battery-low-\(notification.deviceIDs.sorted().joined(separator: "-"))"

        notificationCenter.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Self.addNotification(title: title, body: body, identifier: identifier)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else {
                        return
                    }
                    Self.addNotification(title: title, body: body, identifier: identifier)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private nonisolated static func addNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

enum DeviceBatteryLowBatteryNotificationContent {
    static func make(
        items: [DeviceBatteryItem],
        threshold: Int,
        localization: PluginLocalization
    ) -> DeviceBatteryLowBatteryNotification {
        let sortedItems = items.sorted { left, right in
            let leftLevel = left.clampedLevel ?? Int.max
            let rightLevel = right.clampedLevel ?? Int.max
            if leftLevel != rightLevel {
                return leftLevel < rightLevel
            }

            return left.name.localizedCompare(right.name) == .orderedAscending
        }

        let title: String
        let body: String
        if sortedItems.count == 1, let item = sortedItems.first {
            title = localization.string(
                "notification.lowBattery.single.title",
                defaultValue: "设备电量偏低"
            )
            body = localization.format(
                "notification.lowBattery.single.body",
                defaultValue: "%@ 当前电量 %@，已低于 %d%%。",
                displayName(for: item),
                DeviceBatteryFormatter.percent(item.clampedLevel),
                threshold
            )
        } else {
            title = localization.format(
                "notification.lowBattery.multiple.title",
                defaultValue: "%d 台设备电量偏低",
                sortedItems.count
            )
            body = sortedItems
                .map { item in
                    localization.format(
                        "notification.lowBattery.multiple.item",
                        defaultValue: "%@ %@",
                        displayName(for: item),
                        DeviceBatteryFormatter.percent(item.clampedLevel)
                    )
                }
                .joined(separator: "\n")
        }

        return DeviceBatteryLowBatteryNotification(
            title: title,
            body: body,
            deviceIDs: Set(sortedItems.map(\.id))
        )
    }

    private static func displayName(for item: DeviceBatteryItem) -> String {
        guard let parentName = item.parentName, !parentName.isEmpty else {
            return item.name
        }

        return "\(parentName) \(item.name)"
    }
}

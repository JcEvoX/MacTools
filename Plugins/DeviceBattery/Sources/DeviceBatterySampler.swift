import Foundation
import IOBluetooth
import IOKit
import IOKit.ps

protocol DeviceBatterySampling: Sendable {
    func collectSystemDevices(referenceDate: Date) async -> [DeviceBatteryItem]
}

struct DeviceBatterySampler: DeviceBatterySampling {
    func collectSystemDevices(referenceDate: Date) async -> [DeviceBatteryItem] {
        await Task.detached(priority: .utility) {
            var items: [DeviceBatteryItem] = []
            items.append(contentsOf: Self.collectInternalBattery(referenceDate: referenceDate))
            let bluetoothData = Self.collectBluetoothProfile()
            items.append(contentsOf: Self.collectBluetoothDevices(from: bluetoothData, referenceDate: referenceDate))
            items.append(contentsOf: Self.collectMagicAccessoryDevices(from: bluetoothData, referenceDate: referenceDate))
            return Self.deduplicated(items)
        }.value
    }

    private static func collectInternalBattery(referenceDate: Date) -> [DeviceBatteryItem] {
        guard
            let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo)?.takeRetainedValue() as? [CFTypeRef],
            !powerSources.isEmpty
        else {
            return []
        }

        var fallbackDescription: [String: Any]?
        var batteryDescription: [String: Any]?

        for source in powerSources {
            guard let description = IOPSGetPowerSourceDescription(powerSourcesInfo, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            fallbackDescription = fallbackDescription ?? description
            if description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                batteryDescription = description
                break
            }
        }

        guard let description = batteryDescription ?? fallbackDescription else {
            return []
        }

        let maxCapacity = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
        let currentCapacity = min(max(description[kIOPSCurrentCapacityKey] as? Int ?? 0, 0), maxCapacity)
        let level = Int((Double(currentCapacity) / Double(maxCapacity) * 100).rounded())
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = (description[kIOPSIsChargedKey] as? Bool) ?? (level >= 100)
        let powerSource = description[kIOPSPowerSourceStateKey] as? String ?? ""
        let chargeState = batteryChargeState(
            level: level,
            isCharging: isCharging,
            isCharged: isCharged,
            powerSource: powerSource
        )
        let name = description[kIOPSNameKey] as? String

        return [
            DeviceBatteryItem(
                id: "internal-battery",
                name: name?.isEmpty == false ? name! : "MacBook 电池",
                model: nil,
                kind: .internalBattery,
                level: level,
                chargeState: chargeState,
                parentName: nil,
                source: "IOPowerSources",
                lastUpdated: referenceDate,
                isConnected: true,
                detail: internalBatteryDetail(description: description, chargeState: chargeState)
            )
        ]
    }

    private static func batteryChargeState(
        level: Int,
        isCharging: Bool,
        isCharged: Bool,
        powerSource: String
    ) -> DeviceBatteryChargeState {
        if isCharged || level >= 100 {
            return .charged
        }
        if isCharging {
            return .charging
        }
        if powerSource == "AC Power" {
            return .plugged
        }
        return .normal
    }

    private static func internalBatteryDetail(
        description: [String: Any],
        chargeState: DeviceBatteryChargeState
    ) -> String {
        let timeKey = chargeState == .charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
        guard let minutes = description[timeKey] as? Int, minutes > 0 else {
            return chargeState.title
        }

        return "\(chargeState.title) \(minutes / 60)小时\(minutes % 60)分"
    }

    private static func collectBluetoothProfile() -> BluetoothProfile {
        guard let output = runCommand(
            path: "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json"],
            timeout: 3
        ) else {
            return BluetoothProfile(connectedDevices: [])
        }

        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawSections = json["SPBluetoothDataType"] as? [[String: Any]],
            let section = rawSections.first
        else {
            return BluetoothProfile(connectedDevices: [])
        }

        return BluetoothProfile(connectedDevices: parseBluetoothDevices(from: section["device_connected"]))
    }

    private static func parseBluetoothDevices(from value: Any?) -> [BluetoothProfileDevice] {
        guard let rawDevices = value as? [[String: Any]] else {
            return []
        }

        return rawDevices.compactMap { rawDevice in
            guard let name = rawDevice.keys.first,
                  let info = rawDevice[name] as? [String: Any]
            else {
                return nil
            }

            return BluetoothProfileDevice(name: name, info: info)
        }
    }

    private static func collectBluetoothDevices(
        from profile: BluetoothProfile,
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        var items: [DeviceBatteryItem] = []

        for device in profile.connectedDevices {
            let productID = stringValue(device.info["device_productID"])
            let model = productID.flatMap { HeadphoneModelCatalog.modelName(forProductID: $0) }
            let parentID = normalizedIdentifier(device.info["device_address"]) ?? normalizedIdentifier(productID) ?? device.name

            appendBluetoothLevel(
                to: &items,
                name: device.name,
                suffix: nil,
                fieldName: "device_batteryLevelMain",
                device: device,
                id: parentID,
                kind: inferredKind(device: device, field: "main"),
                model: model,
                parentName: nil,
                referenceDate: referenceDate
            )
            appendBluetoothLevel(
                to: &items,
                name: "\(device.name) 充电盒",
                suffix: "case",
                fieldName: "device_batteryLevelCase",
                device: device,
                id: parentID,
                kind: .airPodsPart,
                model: model,
                parentName: device.name,
                referenceDate: referenceDate
            )
            appendBluetoothLevel(
                to: &items,
                name: "\(device.name) 左耳",
                suffix: "left",
                fieldName: "device_batteryLevelLeft",
                device: device,
                id: parentID,
                kind: .airPodsPart,
                model: model,
                parentName: "\(device.name) 充电盒",
                referenceDate: referenceDate
            )
            appendBluetoothLevel(
                to: &items,
                name: "\(device.name) 右耳",
                suffix: "right",
                fieldName: "device_batteryLevelRight",
                device: device,
                id: parentID,
                kind: .airPodsPart,
                model: model,
                parentName: "\(device.name) 充电盒",
                referenceDate: referenceDate
            )
        }

        items.append(contentsOf: collectIOBluetoothBattery(from: profile, referenceDate: referenceDate))
        return items
    }

    private static func appendBluetoothLevel(
        to items: inout [DeviceBatteryItem],
        name: String,
        suffix: String?,
        fieldName: String,
        device: BluetoothProfileDevice,
        id: String,
        kind: DeviceBatteryKind,
        model: String?,
        parentName: String?,
        referenceDate: Date
    ) {
        guard let level = batteryLevel(from: device.info[fieldName]) else {
            return
        }

        let itemID = suffix.map { "\(id)-\($0)" } ?? id
        items.append(
            DeviceBatteryItem(
                id: "bluetooth-\(itemID)",
                name: name,
                model: model,
                kind: kind,
                level: level,
                chargeState: .normal,
                parentName: parentName,
                source: "system_profiler",
                lastUpdated: referenceDate,
                isConnected: true,
                detail: device.info["device_minorType"] as? String
            )
        )
    }

    private static func collectIOBluetoothBattery(
        from profile: BluetoothProfile,
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            return []
        }

        return devices.compactMap { device in
            guard device.isConnected(),
                  let level = device.pluginBatteryPercentSingle,
                  level > 0,
                  let name = device.name,
                  !name.isEmpty
            else {
                return nil
            }

            let address = normalizedIdentifier(device.addressString) ?? name
            let profileDevice = profile.connectedDevices.first { normalizedIdentifier($0.info["device_address"]) == address }
            let kind = profileDevice.map { inferredKind(device: $0, field: "single") } ?? .bluetooth
            return DeviceBatteryItem(
                id: "iobluetooth-\(address)",
                name: name,
                model: nil,
                kind: kind,
                level: level,
                chargeState: .normal,
                parentName: nil,
                source: "IOBluetooth",
                lastUpdated: referenceDate,
                isConnected: true,
                detail: profileDevice?.info["device_minorType"] as? String
            )
        }
    }

    private static func collectMagicAccessoryDevices(
        from profile: BluetoothProfile,
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        let classes = [
            "AppleDeviceManagementHIDEventService",
            "AppleBluetoothHIDKeyboard",
            "BNBTrackpadDevice",
            "BNBMouseDevice"
        ]

        return classes.flatMap { serviceClass in
            collectIORegistryBatteryDevices(
                matchingService: serviceClass,
                profile: profile,
                referenceDate: referenceDate
            )
        }
    }

    private static func collectIORegistryBatteryDevices(
        matchingService serviceClass: String,
        profile: BluetoothProfile,
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        var iterator = io_iterator_t()
        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching(serviceClass),
            &iterator
        )
        guard result == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var items: [DeviceBatteryItem] = []
        while true {
            let object = IOIteratorNext(iterator)
            guard object != 0 else {
                break
            }
            defer { IOObjectRelease(object) }

            guard let item = makeIORegistryBatteryItem(
                object: object,
                serviceClass: serviceClass,
                profile: profile,
                referenceDate: referenceDate
            ) else {
                continue
            }

            items.append(item)
        }

        return items
    }

    private static func makeIORegistryBatteryItem(
        object: io_object_t,
        serviceClass: String,
        profile: BluetoothProfile,
        referenceDate: Date
    ) -> DeviceBatteryItem? {
        guard let level = intProperty("BatteryPercent", object: object),
              (0...100).contains(level)
        else {
            return nil
        }

        let rawAddress = stringProperty("DeviceAddress", object: object)
        let address = normalizedIdentifier(rawAddress)
        let productName = stringProperty("Product", object: object)
        guard productName?.localizedCaseInsensitiveContains("Internal") != true else {
            return nil
        }

        let matchedProfileDevice = profile.connectedDevices.first { profileDevice in
            normalizedIdentifier(profileDevice.info["device_address"]) == address
        }
        let name = firstNonEmpty(matchedProfileDevice?.name, productName, serviceClass)
        let statusFlags = intProperty("BatteryStatusFlags", object: object)
        let chargeState: DeviceBatteryChargeState = statusFlags == 4 ? .normal : (statusFlags ?? 0) > 0 ? .charging : .normal
        let kind = inferredMagicKind(productName: productName, profileDevice: matchedProfileDevice)

        return DeviceBatteryItem(
            id: "ioregistry-\(address ?? name)-\(serviceClass)",
            name: name,
            model: productName,
            kind: kind,
            level: level,
            chargeState: chargeState,
            parentName: nil,
            source: "IORegistry",
            lastUpdated: referenceDate,
            isConnected: true,
            detail: matchedProfileDevice?.info["device_minorType"] as? String
        )
    }

    private static func inferredKind(
        device: BluetoothProfileDevice,
        field: String
    ) -> DeviceBatteryKind {
        let name = device.name.lowercased()
        let type = (device.info["device_minorType"] as? String ?? "").lowercased()
        let vendorID = (device.info["device_vendorID"] as? String ?? "").lowercased()

        if field != "main" || name.contains("airpods") || name.contains("beats") {
            return .airPodsPart
        }
        if vendorID == "0x004c" {
            return .magicAccessory
        }
        if type.contains("mouse") || type.contains("keyboard") || type.contains("trackpad") {
            return .magicAccessory
        }
        return .bluetooth
    }

    private static func inferredMagicKind(
        productName: String?,
        profileDevice: BluetoothProfileDevice?
    ) -> DeviceBatteryKind {
        let combined = [productName, profileDevice?.info["device_minorType"] as? String]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if combined.contains("mouse") || combined.contains("keyboard") || combined.contains("trackpad") {
            return .magicAccessory
        }
        return .bluetooth
    }

    private static func deduplicated(_ items: [DeviceBatteryItem]) -> [DeviceBatteryItem] {
        var bestByNameAndKind: [String: DeviceBatteryItem] = [:]
        for item in items {
            let key = "\(item.kind.title)-\(item.name.lowercased())-\(item.parentName ?? "")"
            if let existing = bestByNameAndKind[key] {
                bestByNameAndKind[key] = preferredItem(existing, item)
            } else {
                bestByNameAndKind[key] = item
            }
        }

        return Array(bestByNameAndKind.values)
    }

    private static func preferredItem(
        _ left: DeviceBatteryItem,
        _ right: DeviceBatteryItem
    ) -> DeviceBatteryItem {
        let sourceRank = ["IORegistry": 0, "IOBluetooth": 1, "system_profiler": 2, "IOPowerSources": 0]
        let leftRank = sourceRank[left.source] ?? 10
        let rightRank = sourceRank[right.source] ?? 10
        if leftRank != rightRank {
            return leftRank < rightRank ? left : right
        }

        return left.lastUpdated ?? .distantPast >= right.lastUpdated ?? .distantPast ? left : right
    }

    private static func batteryLevel(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            let level = number.intValue
            return (0...100).contains(level) ? level : nil
        }

        guard let string = value as? String else {
            return nil
        }

        let digits = string
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let level = Int(digits), (0...100).contains(level) else {
            return nil
        }

        return level
    }

    private static func normalizedIdentifier(_ value: Any?) -> String? {
        guard let rawValue = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return nil
        }

        return rawValue
            .replacingOccurrences(of: "-", with: ":")
            .uppercased()
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }

        return "蓝牙设备"
    }

    private static func intProperty(_ key: String, object: io_object_t) -> Int? {
        guard let value = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }

        return value.takeRetainedValue() as? Int
    }

    private static func stringProperty(_ key: String, object: io_object_t) -> String? {
        guard let value = IORegistryEntryCreateCFProperty(object, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }

        return value.takeRetainedValue() as? String
    }

    private static func runCommand(
        path: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
            return nil
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.03)
        }

        guard !process.isRunning else {
            process.terminate()
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
            return nil
        }

        process.waitUntilExit()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        outputPipe.fileHandleForReading.closeFile()
        errorPipe.fileHandleForReading.closeFile()

        return String(data: data, encoding: .utf8)
    }
}

private struct BluetoothProfile {
    let connectedDevices: [BluetoothProfileDevice]
}

private struct BluetoothProfileDevice {
    let name: String
    let info: [String: Any]
}

private extension IOBluetoothDevice {
    var pluginBatteryPercentSingle: Int? {
        pluginValue(forKey: "batteryPercentSingle") as? Int
    }

    func pluginValue(forKey key: String) -> Any? {
        guard responds(to: Selector(key)) else {
            return nil
        }

        return value(forKey: key)
    }
}

enum HeadphoneModelCatalog {
    private static let modelNamesByProductID: [String: String] = [
        "2002": "AirPods",
        "2003": "Powerbeats3",
        "2005": "BeatsX",
        "2006": "Beats Solo3",
        "200e": "AirPods Pro",
        "200f": "Powerbeats Pro",
        "2013": "AirPods Max",
        "2014": "AirPods Pro",
        "2016": "Beats Studio Buds",
        "2019": "AirPods 3",
        "201b": "Beats Fit Pro",
        "201d": "AirPods Pro 2",
        "2024": "Beats Studio Pro",
        "2026": "Beats Solo Buds",
        "2027": "Powerbeats Pro 2"
    ]

    static func modelName(forProductID productID: String) -> String? {
        let normalized = productID
            .replacingOccurrences(of: "0x", with: "")
            .lowercased()
        return modelNamesByProductID[normalized]
    }
}

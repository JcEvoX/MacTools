import Foundation
import CoreBluetooth
import IOBluetooth
import IOKit
import IOKit.ps

protocol DeviceBatterySampling: Sendable {
    func collectSystemDevices(referenceDate: Date) async -> [DeviceBatteryItem]
}

struct DeviceBatterySampler: DeviceBatterySampling {
    private static let bluetoothPowerLogCache = DeviceBatteryBluetoothPowerLogCache()
    private static let bluetoothPowerLogLookback = "1m"
    private static let bluetoothPowerLogTimeout: TimeInterval = 1.5

    func collectSystemDevices(referenceDate: Date) async -> [DeviceBatteryItem] {
        let baseSample = await Task.detached(priority: .utility) {
            var items: [DeviceBatteryItem] = []
            items.append(contentsOf: Self.collectInternalBattery(referenceDate: referenceDate))
            let bluetoothData = Self.collectBluetoothProfile()
            items.append(contentsOf: Self.collectBluetoothDevices(from: bluetoothData, referenceDate: referenceDate))
            items.append(contentsOf: Self.collectBluetoothPowerLogDevices(
                from: bluetoothData,
                existingItems: items,
                referenceDate: referenceDate
            ))
            items.append(contentsOf: Self.collectMagicAccessoryDevices(from: bluetoothData, referenceDate: referenceDate))
            return DeviceBatteryBaseSample(
                items: Self.deduplicated(items),
                bluetoothBatteryTargets: Self.bluetoothBatteryTargets(from: bluetoothData)
            )
        }.value

        let bluetoothBatteryItems = await DeviceBatteryBLEBatteryReader.collectBatteryDevices(
            targets: baseSample.bluetoothBatteryTargets,
            referenceDate: referenceDate
        )
        return Self.deduplicated(baseSample.items + bluetoothBatteryItems)
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
        let name = internalBatteryDisplayName(rawName: description[kIOPSNameKey] as? String)

        return [
            DeviceBatteryItem(
                id: "internal-battery",
                name: name,
                model: nil,
                kind: .internalBattery,
                level: level,
                chargeState: chargeState,
                parentName: nil,
                source: "IOPowerSources",
                lastUpdated: referenceDate,
                isConnected: true,
                detail: internalBatteryDetail(description: description, chargeState: chargeState),
                componentIdentity: nil
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

    private static func internalBatteryDisplayName(rawName: String?) -> String {
        let cleanedName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowercasedName = cleanedName.lowercased()
        let isSystemIdentifier = cleanedName.isEmpty
            || lowercasedName.contains("internal")
            || lowercasedName == "battery"
            || lowercasedName.contains("battery-")

        if !isSystemIdentifier {
            return cleanedName
        }

        let hostName = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hostName.isEmpty ? "Mac 电池" : hostName
    }

    private static func collectBluetoothProfile() -> BluetoothProfile {
        guard let output = runCommand(
            path: "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-json"],
            timeout: 3
        ) else {
            return BluetoothProfile(connectedDevices: [], batteryDevices: [])
        }

        return bluetoothProfile(fromSystemProfilerOutput: output)
    }

    private static func bluetoothProfile(
        fromSystemProfilerOutput output: String
    ) -> BluetoothProfile {
        guard
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rawSections = json["SPBluetoothDataType"] as? [[String: Any]],
            let section = rawSections.first
        else {
            return BluetoothProfile(connectedDevices: [], batteryDevices: [])
        }

        let connectedDevices = parseBluetoothDevices(
            from: section["device_connected"],
            isConnected: true
        )
        let disconnectedBatteryDevices = parseBluetoothDevices(
            from: section["device_not_connected"],
            isConnected: false
        )
            .filter { hasBluetoothBatteryFields($0.info) }

        return BluetoothProfile(
            connectedDevices: connectedDevices,
            batteryDevices: mergedBatteryDevices(
                connectedDevices + disconnectedBatteryDevices
            )
        )
    }

    static func bluetoothProfileBatteryItems(
        fromSystemProfilerOutput output: String,
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        collectBluetoothProfileBatteryItems(
            from: bluetoothProfile(fromSystemProfilerOutput: output),
            referenceDate: referenceDate
        )
    }

    private static func parseBluetoothDevices(
        from value: Any?,
        isConnected: Bool
    ) -> [BluetoothProfileDevice] {
        guard let rawDevices = value as? [[String: Any]] else {
            return []
        }

        return rawDevices.compactMap { rawDevice in
            guard let name = rawDevice.keys.first,
                  let info = rawDevice[name] as? [String: Any]
            else {
                return nil
            }

            return BluetoothProfileDevice(
                name: name,
                info: info,
                isConnected: isConnected
            )
        }
    }

    private static func hasBluetoothBatteryFields(_ info: [String: Any]) -> Bool {
        [
            "device_batteryLevelMain",
            "device_batteryLevelCase",
            "device_batteryLevelLeft",
            "device_batteryLevelRight"
        ]
            .contains { batteryValue(from: info[$0]) != nil }
    }

    private static func mergedBatteryDevices(_ devices: [BluetoothProfileDevice]) -> [BluetoothProfileDevice] {
        var mergedByKey: [String: BluetoothProfileDevice] = [:]
        var orderedKeys: [String] = []

        for device in devices {
            let key = normalizedIdentifier(device.info["device_address"])
                ?? normalizedDeviceName(device.name)
            if let existing = mergedByKey[key] {
                if !existing.isConnected, device.isConnected {
                    mergedByKey[key] = device
                }
            } else {
                mergedByKey[key] = device
                orderedKeys.append(key)
            }
        }

        return orderedKeys.compactMap { mergedByKey[$0] }
    }

    private static func collectBluetoothPowerLogDevices(
        from profile: BluetoothProfile,
        existingItems: [DeviceBatteryItem],
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        let targets = bluetoothBatteryTargets(from: profile).filter { target in
            needsBluetoothPowerLogFallback(target: target, existingItems: existingItems)
        }
        guard !targets.isEmpty else {
            return []
        }

        let componentTargets = targets.filter { supportsComponentPowerLog(target: $0) }
        let regularTargets = targets.filter { !supportsComponentPowerLog(target: $0) }
        let recentReadings = collectBluetoothPowerLogReadings(
            targets: targets,
            lookback: bluetoothPowerLogLookback,
            timeout: bluetoothPowerLogTimeout
        )

        var items: [DeviceBatteryItem] = []
        if !componentTargets.isEmpty {
            let componentReadings = recentReadings.filter { reading in
                matchingBluetoothPowerLogTarget(reading, in: componentTargets) != nil
            }
            items.append(contentsOf: bluetoothPowerLogItems(
                from: componentReadings,
                targets: componentTargets,
                referenceDate: referenceDate
            ))
        }

        if !regularTargets.isEmpty {
            let regularReadings = recentReadings.filter { reading in
                matchingBluetoothPowerLogTarget(reading, in: regularTargets) != nil
            }
            bluetoothPowerLogCache.update(readings: regularReadings, at: referenceDate)

            let regularItems = bluetoothPowerLogItems(
                from: regularReadings,
                targets: regularTargets,
                referenceDate: referenceDate
            )
            if !regularItems.isEmpty {
                items.append(contentsOf: regularItems)
            } else {
                items.append(contentsOf: bluetoothPowerLogItems(
                    from: bluetoothPowerLogCache.readings(
                        matching: regularTargets,
                        referenceDate: referenceDate
                    ),
                    targets: regularTargets,
                    referenceDate: referenceDate
                ))
            }
        }

        return DeviceBatteryItemNormalizer.removingRedundantComponentAggregates(items)
    }

    private static let bluetoothPowerLogPredicate = #"subsystem == "com.apple.bluetooth" AND category == "CBPowerSource" AND eventMessage CONTAINS "Battery""#

    private static func collectBluetoothPowerLogReadings(
        targets: [BluetoothBatteryTarget],
        lookback: String,
        timeout: TimeInterval
    ) -> [DeviceBatteryBluetoothPowerLogReading] {
        guard let output = runCommand(
            path: "/usr/bin/log",
            arguments: [
                "show",
                "--process",
                "bluetoothd",
                "--info",
                "--last",
                lookback,
                "--style",
                "compact",
                "--predicate",
                bluetoothPowerLogPredicate(for: targets)
            ],
            timeout: timeout,
            outputLineFilter: { line in
                isBluetoothPowerLogLine(line, matching: targets)
            }
        ) else {
            return []
        }

        return DeviceBatteryBluetoothPowerLogParser.readings(from: output)
    }

    private static func bluetoothPowerLogPredicate(for targets: [BluetoothBatteryTarget]) -> String {
        let targetPredicates = targets.flatMap { target -> [String] in
            var predicates: [String] = []

            let name = target.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                predicates.append(#"eventMessage CONTAINS[c] "\#(escapedPredicateString(name))""#)
            }

            let vendorID = target.vendorID?.trimmingCharacters(in: .whitespacesAndNewlines)
            let productID = target.productID?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let vendorID, !vendorID.isEmpty, let productID, !productID.isEmpty {
                predicates.append(
                    #"(eventMessage CONTAINS "\#(escapedPredicateString(vendorID))" AND eventMessage CONTAINS "\#(escapedPredicateString(productID))")"#
                )
            } else if let productID, !productID.isEmpty {
                predicates.append(#"eventMessage CONTAINS "\#(escapedPredicateString(productID))""#)
            }

            return predicates
        }

        guard !targetPredicates.isEmpty else {
            return bluetoothPowerLogPredicate
        }

        return "\(bluetoothPowerLogPredicate) AND (\(targetPredicates.joined(separator: " OR ")))"
    }

    private static func escapedPredicateString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func isBluetoothPowerLogLine(
        _ line: String,
        matching targets: [BluetoothBatteryTarget]
    ) -> Bool {
        guard line.contains("CBPowerSource"),
              line.contains("Power source updated"),
              line.contains("Battery")
        else {
            return false
        }

        return targets.contains { target in
            bluetoothPowerLogLine(line, matches: target)
        }
    }

    static func isBluetoothPowerLogLine(
        _ line: String,
        matchingName name: String,
        vendorID: String?,
        productID: String?
    ) -> Bool {
        guard line.contains("CBPowerSource"),
              line.contains("Power source updated"),
              line.contains("Battery")
        else {
            return false
        }

        if line.localizedCaseInsensitiveContains(name) {
            return true
        }

        let normalizedLine = line.uppercased()
        if let vendorID = normalizedHexIdentifier(vendorID),
           let productID = normalizedHexIdentifier(productID),
           normalizedLine.contains("0X\(vendorID)"),
           normalizedLine.contains("0X\(productID)") {
            return true
        }

        return false
    }

    private static func bluetoothPowerLogLine(
        _ line: String,
        matches target: BluetoothBatteryTarget
    ) -> Bool {
        isBluetoothPowerLogLine(
            line,
            matchingName: target.name,
            vendorID: target.vendorID,
            productID: target.productID
        )
    }

    private static func bluetoothPowerLogItems(
        from readings: [DeviceBatteryBluetoothPowerLogReading],
        targets: [BluetoothBatteryTarget],
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        readings.compactMap { reading in
            guard let target = matchingBluetoothPowerLogTarget(reading, in: targets) else {
                return nil
            }

            return DeviceBatteryItem(
                id: powerLogItemID(reading: reading, target: target),
                name: powerLogItemName(reading: reading, target: target),
                model: target.model,
                kind: reading.component == nil ? target.kind : .airPodsPart,
                level: reading.level,
                chargeState: reading.chargeState,
                parentName: powerLogParentName(reading: reading, target: target),
                source: "BluetoothPowerLog",
                lastUpdated: referenceDate,
                isConnected: target.isConnected,
                detail: reading.deviceType ?? target.detail,
                componentIdentity: powerLogComponentIdentity(reading: reading, target: target)
            )
        }
    }

    private static func needsBluetoothPowerLogFallback(
        target: BluetoothBatteryTarget,
        existingItems: [DeviceBatteryItem]
    ) -> Bool {
        if supportsComponentPowerLog(target: target) {
            return true
        }

        guard target.isConnected else {
            return false
        }

        if normalizedHexIdentifier(target.vendorID) == "004C" {
            return false
        }

        let targetName = normalizedDeviceName(target.name)
        return !existingItems.contains { item in
            item.parentName == nil
                && normalizedDeviceName(item.name) == targetName
                && item.clampedLevel != nil
        }
    }

    private static func powerLogItemName(
        reading: DeviceBatteryBluetoothPowerLogReading,
        target: BluetoothBatteryTarget
    ) -> String {
        guard let component = reading.component else {
            return target.name
        }

        return "\(target.name) \(component.title)"
    }

    private static func powerLogItemID(
        reading: DeviceBatteryBluetoothPowerLogReading,
        target: BluetoothBatteryTarget
    ) -> String {
        let baseID = target.address ?? target.id
        guard let component = reading.component else {
            return "bluetooth-powerlog-\(baseID)"
        }

        return "bluetooth-powerlog-\(baseID)-\(component.idSuffix)"
    }

    private static func powerLogParentName(
        reading: DeviceBatteryBluetoothPowerLogReading,
        target: BluetoothBatteryTarget
    ) -> String? {
        switch reading.component {
        case nil:
            return nil
        case .chargingCase:
            return target.name
        case .left, .right:
            return "\(target.name) 充电盒"
        }
    }

    private static func powerLogComponentIdentity(
        reading: DeviceBatteryBluetoothPowerLogReading,
        target: BluetoothBatteryTarget
    ) -> DeviceBatteryComponentIdentity? {
        guard supportsComponentPowerLog(target: target) || reading.component != nil else {
            return nil
        }

        return DeviceBatteryComponentIdentity(
            groupID: target.componentGroupID,
            role: reading.component?.componentRole ?? .aggregate
        )
    }

    private static func supportsComponentPowerLog(target: BluetoothBatteryTarget) -> Bool {
        guard normalizedHexIdentifier(target.vendorID) == "004C" else {
            return false
        }

        let haystack = [
            target.name,
            target.model,
            target.detail
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        return target.kind == .airPodsPart
            || haystack.contains("airpods")
            || haystack.contains("beats")
            || haystack.contains("headphone")
            || haystack.contains("headset")
    }

    private static func collectBluetoothDevices(
        from profile: BluetoothProfile,
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        var items = collectBluetoothProfileBatteryItems(
            from: profile,
            referenceDate: referenceDate
        )
        items.append(contentsOf: collectIOBluetoothBattery(from: profile, referenceDate: referenceDate))
        return items
    }

    private static func collectBluetoothProfileBatteryItems(
        from profile: BluetoothProfile,
        referenceDate: Date
    ) -> [DeviceBatteryItem] {
        var items: [DeviceBatteryItem] = []

        for device in profile.batteryDevices {
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
                componentRole: hasBluetoothComponentBatteryFields(device.info) ? .aggregate : nil,
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
                componentRole: .chargingCase,
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
                componentRole: .left,
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
                componentRole: .right,
                referenceDate: referenceDate
            )
        }

        return DeviceBatteryItemNormalizer.removingRedundantComponentAggregates(items)
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
        componentRole: DeviceBatteryComponentRole?,
        referenceDate: Date
    ) {
        guard let batteryValue = batteryValue(from: device.info[fieldName]) else {
            return
        }

        let itemID = suffix.map { "\(id)-\($0)" } ?? id
        items.append(
            DeviceBatteryItem(
                id: "bluetooth-\(itemID)",
                name: name,
                model: model,
                kind: kind,
                level: batteryValue.level,
                chargeState: batteryValue.chargeState,
                parentName: parentName,
                source: "system_profiler",
                lastUpdated: referenceDate,
                isConnected: device.isConnected,
                detail: device.info["device_minorType"] as? String,
                componentIdentity: componentRole.map {
                    DeviceBatteryComponentIdentity(groupID: id, role: $0)
                }
            )
        )
    }

    private static func hasBluetoothComponentBatteryFields(_ info: [String: Any]) -> Bool {
        [
            "device_batteryLevelCase",
            "device_batteryLevelLeft",
            "device_batteryLevelRight"
        ]
            .contains { batteryValue(from: info[$0]) != nil }
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
                detail: profileDevice?.info["device_minorType"] as? String,
                componentIdentity: componentAggregateIdentity(groupID: address, kind: kind)
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
            detail: matchedProfileDevice?.info["device_minorType"] as? String,
            componentIdentity: nil
        )
    }

    fileprivate static func componentAggregateIdentity(
        groupID: String,
        kind: DeviceBatteryKind
    ) -> DeviceBatteryComponentIdentity? {
        guard kind == .airPodsPart else {
            return nil
        }

        return DeviceBatteryComponentIdentity(groupID: groupID, role: .aggregate)
    }

    private static func inferredKind(
        device: BluetoothProfileDevice,
        field: String
    ) -> DeviceBatteryKind {
        inferredBluetoothKind(
            name: device.name,
            minorType: device.info["device_minorType"] as? String,
            vendorID: device.info["device_vendorID"] as? String,
            field: field
        )
    }

    static func inferredBluetoothKind(
        name: String,
        minorType: String?,
        vendorID: String?,
        field: String
    ) -> DeviceBatteryKind {
        let name = name.lowercased()
        let type = (minorType ?? "").lowercased()
        let vendorID = (vendorID ?? "").lowercased()

        if field == "case" || field == "left" || field == "right" {
            return .airPodsPart
        }
        if field != "main" || name.contains("airpods") || name.contains("beats") {
            if name.contains("airpods")
                || name.contains("beats")
                || type.contains("headphone")
                || type.contains("headset") {
                return .airPodsPart
            }
        }
        if vendorID == "0x004c" {
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
            if combined.contains("apple") || combined.contains("magic") {
                return .magicAccessory
            }
            if profileDevice?.info["device_vendorID"] as? String == "0x004c" {
                return .magicAccessory
            }
            return .bluetooth
        }
        if combined.contains("magic") {
            return .magicAccessory
        }
        return .bluetooth
    }

    private static func bluetoothBatteryTargets(from profile: BluetoothProfile) -> [BluetoothBatteryTarget] {
        profile.batteryDevices.map { device in
            let productID = stringValue(device.info["device_productID"])
            let vendorID = stringValue(device.info["device_vendorID"])
            let model = productID.flatMap { HeadphoneModelCatalog.modelName(forProductID: $0) }
            return BluetoothBatteryTarget(
                id: normalizedIdentifier(device.info["device_address"]) ?? device.name,
                name: device.name,
                address: normalizedIdentifier(device.info["device_address"]),
                vendorID: vendorID,
                productID: productID,
                model: model,
                kind: inferredKind(device: device, field: "single"),
                detail: device.info["device_minorType"] as? String,
                isConnected: device.isConnected
            )
        }
    }

    fileprivate static func matchingBluetoothPowerLogTarget(
        _ reading: DeviceBatteryBluetoothPowerLogReading,
        in targets: [BluetoothBatteryTarget]
    ) -> BluetoothBatteryTarget? {
        let candidates = targets.filter { target in
            normalizedDeviceName(target.name) == normalizedDeviceName(reading.name)
                && bluetoothIdentifiersMatch(reading: reading, target: target)
        }

        if candidates.count == 1 {
            return candidates[0]
        }

        return candidates.first { target in
            normalizedHexIdentifier(target.vendorID) == normalizedHexIdentifier(reading.vendorID)
                && normalizedHexIdentifier(target.productID) == normalizedHexIdentifier(reading.productID)
        }
    }

    private static func bluetoothIdentifiersMatch(
        reading: DeviceBatteryBluetoothPowerLogReading,
        target: BluetoothBatteryTarget
    ) -> Bool {
        if let readingVendorID = normalizedHexIdentifier(reading.vendorID),
           let targetVendorID = normalizedHexIdentifier(target.vendorID),
           readingVendorID != targetVendorID {
            return false
        }

        if let readingProductID = normalizedHexIdentifier(reading.productID),
           let targetProductID = normalizedHexIdentifier(target.productID),
           readingProductID != targetProductID {
            return false
        }

        return true
    }

    private static func normalizedDeviceName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func normalizedHexIdentifier(_ value: String?) -> String? {
        let cleaned = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned, !cleaned.isEmpty else {
            return nil
        }

        return cleaned.uppercased()
    }

    private static func deduplicated(_ items: [DeviceBatteryItem]) -> [DeviceBatteryItem] {
        var bestByNameAndKind: [String: DeviceBatteryItem] = [:]
        for item in DeviceBatteryItemNormalizer.removingRedundantComponentAggregates(items) {
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
        if left.chargeState.isActiveChargingState != right.chargeState.isActiveChargingState {
            return left.chargeState.isActiveChargingState ? left : right
        }

        let sourceRank = [
            "IORegistry": 0,
            "IOPowerSources": 0,
            "CoreBluetooth": 1,
            "BluetoothPowerLog": 2,
            "IOBluetooth": 3,
            "system_profiler": 4
        ]
        let leftRank = sourceRank[left.source] ?? 10
        let rightRank = sourceRank[right.source] ?? 10
        if leftRank != rightRank {
            return leftRank < rightRank ? left : right
        }

        return left.lastUpdated ?? .distantPast >= right.lastUpdated ?? .distantPast ? left : right
    }

    private static func batteryLevel(from value: Any?) -> Int? {
        batteryValue(from: value)?.level
    }

    private static func batteryValue(from value: Any?) -> (level: Int, chargeState: DeviceBatteryChargeState)? {
        if let number = value as? NSNumber {
            let level = number.intValue
            guard (0...100).contains(level) else {
                return nil
            }
            return (level, .normal)
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

        return (level, digits.hasPrefix("+") ? .charging : .normal)
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
        timeout: TimeInterval,
        outputLineFilter: ((String) -> Bool)? = nil
    ) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputAccumulator = CommandOutputAccumulator(lineFilter: outputLineFilter)
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputAccumulator.append(handle.availableData)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
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
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            outputAccumulator.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
            outputPipe.fileHandleForReading.closeFile()
            errorPipe.fileHandleForReading.closeFile()
            let partialOutput = outputAccumulator.output()
            return outputLineFilter == nil || partialOutput.isEmpty ? nil : partialOutput
        }

        process.waitUntilExit()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputAccumulator.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
        outputPipe.fileHandleForReading.closeFile()
        errorPipe.fileHandleForReading.closeFile()

        return outputAccumulator.output()
    }
}

private final class CommandOutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let lineFilter: ((String) -> Bool)?
    private var bufferedOutput = ""
    private var pendingLine = ""

    init(lineFilter: ((String) -> Bool)?) {
        self.lineFilter = lineFilter
    }

    func append(_ data: Data) {
        guard !data.isEmpty,
              let chunk = String(data: data, encoding: .utf8)
        else {
            return
        }

        lock.lock()
        if let lineFilter {
            appendFiltered(chunk, lineFilter: lineFilter)
        } else {
            bufferedOutput.append(chunk)
        }
        lock.unlock()
    }

    func output() -> String {
        lock.lock()
        if let lineFilter,
           !pendingLine.isEmpty,
           lineFilter(pendingLine) {
            bufferedOutput.append(pendingLine)
            bufferedOutput.append("\n")
        }
        pendingLine = ""
        let currentOutput = bufferedOutput
        lock.unlock()
        return currentOutput
    }

    private func appendFiltered(
        _ chunk: String,
        lineFilter: (String) -> Bool
    ) {
        pendingLine.append(chunk)
        let lines = pendingLine.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else {
            return
        }

        for line in lines.dropLast() {
            let text = String(line)
            if lineFilter(text) {
                bufferedOutput.append(text)
                bufferedOutput.append("\n")
            }
        }

        pendingLine = String(lines.last ?? "")
    }
}

private struct BluetoothProfile {
    let connectedDevices: [BluetoothProfileDevice]
    let batteryDevices: [BluetoothProfileDevice]
}

private struct BluetoothProfileDevice {
    let name: String
    let info: [String: Any]
    let isConnected: Bool
}

private struct DeviceBatteryBaseSample: Sendable {
    let items: [DeviceBatteryItem]
    let bluetoothBatteryTargets: [BluetoothBatteryTarget]
}

fileprivate struct BluetoothBatteryTarget: Sendable {
    let id: String
    let name: String
    let address: String?
    let vendorID: String?
    let productID: String?
    let model: String?
    let kind: DeviceBatteryKind
    let detail: String?
    let isConnected: Bool

    var componentGroupID: String {
        address ?? id
    }
}

private final class DeviceBatteryBluetoothPowerLogCache: @unchecked Sendable {
    private struct Entry {
        let reading: DeviceBatteryBluetoothPowerLogReading
        let updatedAt: Date
    }

    private let lock = NSLock()
    private var entriesByIdentity: [String: Entry] = [:]
    private let ttl: TimeInterval = 60

    func update(
        readings: [DeviceBatteryBluetoothPowerLogReading],
        at date: Date
    ) {
        guard !readings.isEmpty else {
            return
        }

        lock.lock()
        for reading in readings {
            entriesByIdentity[Self.identityKey(for: reading)] = Entry(
                reading: reading,
                updatedAt: date
            )
        }
        lock.unlock()
    }

    func readings(
        matching targets: [BluetoothBatteryTarget],
        referenceDate: Date
    ) -> [DeviceBatteryBluetoothPowerLogReading] {
        lock.lock()
        defer { lock.unlock() }

        entriesByIdentity = entriesByIdentity.filter { _, entry in
            referenceDate.timeIntervalSince(entry.updatedAt) <= ttl
        }

        return entriesByIdentity.values.compactMap { entry in
            DeviceBatterySampler.matchingBluetoothPowerLogTarget(entry.reading, in: targets) == nil
                ? nil
                : entry.reading
        }
    }

    private static func identityKey(for reading: DeviceBatteryBluetoothPowerLogReading) -> String {
        [
            reading.name,
            reading.vendorID ?? "",
            reading.productID ?? "",
            reading.component?.rawValue ?? "main"
        ]
            .joined(separator: "|")
            .lowercased()
    }
}

struct DeviceBatteryBluetoothPowerLogReading: Equatable, Sendable {
    let name: String
    let vendorID: String?
    let productID: String?
    let deviceType: String?
    let component: DeviceBatteryBluetoothPowerLogComponent?
    let level: Int
    let chargeState: DeviceBatteryChargeState
}

enum DeviceBatteryBluetoothPowerLogComponent: String, Sendable {
    case left
    case right
    case chargingCase

    var title: String {
        switch self {
        case .left:
            return "左耳"
        case .right:
            return "右耳"
        case .chargingCase:
            return "充电盒"
        }
    }

    var idSuffix: String {
        switch self {
        case .left:
            return "left"
        case .right:
            return "right"
        case .chargingCase:
            return "case"
        }
    }

    var componentRole: DeviceBatteryComponentRole {
        switch self {
        case .left:
            return .left
        case .right:
            return .right
        case .chargingCase:
            return .chargingCase
        }
    }
}

enum DeviceBatteryBluetoothPowerLogParser {
    static func readings(from output: String) -> [DeviceBatteryBluetoothPowerLogReading] {
        var latestByIdentity: [String: DeviceBatteryBluetoothPowerLogReading] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            for reading in readings(fromLine: String(line)) {
                latestByIdentity[identityKey(for: reading)] = reading
            }
        }

        return Array(latestByIdentity.values)
    }

    static func reading(from line: String) -> DeviceBatteryBluetoothPowerLogReading? {
        readings(fromLine: line).first { $0.component == nil }
    }

    static func readings(fromLine line: String) -> [DeviceBatteryBluetoothPowerLogReading] {
        guard line.contains("CBPowerSource"),
              line.contains("Power source updated"),
              let name = stringValue(after: "Nm '", before: "'", in: line)
        else {
            return []
        }

        let vendorID = stringValue(after: "VID ", before: " ", in: line)
        let productID = stringValue(after: "PID ", before: " ", in: line)
        let deviceType = stringValue(after: "AcCa ", before: ",", in: line)
        var readings: [DeviceBatteryBluetoothPowerLogReading] = []

        if let batteryValue = batteryPercentValue(after: "Battery ", in: line)
            ?? batteryPercentValue(after: "Battery M ", in: line) {
            readings.append(DeviceBatteryBluetoothPowerLogReading(
                name: name,
                vendorID: vendorID,
                productID: productID,
                deviceType: deviceType,
                component: nil,
                level: min(max(abs(batteryValue.level), 0), 100),
                chargeState: batteryValue.isCharging ? .charging : .normal
            ))
        }

        readings.append(contentsOf: componentBatteryValues(in: line).map { component, batteryValue in
            DeviceBatteryBluetoothPowerLogReading(
                name: name,
                vendorID: vendorID,
                productID: productID,
                deviceType: deviceType,
                component: component,
                level: min(max(abs(batteryValue.level), 0), 100),
                chargeState: batteryValue.isCharging ? .charging : .normal
            )
        })

        return readings
    }

    private static func componentBatteryValues(
        in line: String
    ) -> [(DeviceBatteryBluetoothPowerLogComponent, (level: Int, isCharging: Bool))] {
        [
            (.left, "Left "),
            (.right, "Right "),
            (.chargingCase, "Case ")
        ]
            .compactMap { component, prefix in
                guard let batteryValue = batteryPercentValue(after: prefix, in: line) else {
                    return nil
                }
                return (component, batteryValue)
            }
    }

    private static func identityKey(for reading: DeviceBatteryBluetoothPowerLogReading) -> String {
        [
            reading.name,
            reading.vendorID ?? "",
            reading.productID ?? "",
            reading.component?.rawValue ?? "main"
        ]
            .joined(separator: "|")
            .lowercased()
    }

    private static func stringValue(
        after prefix: String,
        before suffix: Character,
        in text: String
    ) -> String? {
        guard let startRange = text.range(of: prefix) else {
            return nil
        }

        let start = startRange.upperBound
        guard let end = text[start...].firstIndex(of: suffix) else {
            return nil
        }

        let value = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func batteryPercentValue(
        after prefix: String,
        in text: String
    ) -> (level: Int, isCharging: Bool)? {
        guard let startRange = text.range(of: prefix) else {
            return nil
        }

        let remainder = text[startRange.upperBound...]
        var value = ""
        for character in remainder {
            if character == "+" || character == "-" || character.isNumber {
                value.append(character)
                continue
            }
            break
        }

        guard !value.isEmpty else {
            return nil
        }

        guard let level = Int(value) else {
            return nil
        }

        return (level: level, isCharging: value.hasPrefix("+"))
    }
}

@MainActor
private final class DeviceBatteryBLEBatteryReader: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private static let batteryService = CBUUID(string: "180F")
    private static let deviceInformationService = CBUUID(string: "180A")
    private static let batteryLevelCharacteristic = CBUUID(string: "2A19")
    private static let modelNumberCharacteristic = CBUUID(string: "2A24")
    private static let manufacturerNameCharacteristic = CBUUID(string: "2A29")

    private let targetsByName: [String: BluetoothBatteryTarget]
    private let referenceDate: Date
    private var centralManager: CBCentralManager?
    private var continuations: [CheckedContinuation<[DeviceBatteryItem], Never>] = []
    private var peripheralsByID: [UUID: CBPeripheral] = [:]
    private var pendingPeripheralIDs: Set<UUID> = []
    private var readingByID: [UUID: BluetoothBatteryReading] = [:]
    private var discoveredNames: Set<String> = []
    private var timeoutTask: Task<Void, Never>?
    private var didFinish = false

    static func collectBatteryDevices(
        targets: [BluetoothBatteryTarget],
        referenceDate: Date
    ) async -> [DeviceBatteryItem] {
        let eligibleTargets = targets.filter { target in
            target.isConnected && (target.kind == .bluetooth || target.kind == .magicAccessory)
        }
        guard !eligibleTargets.isEmpty else {
            return []
        }

        let reader = DeviceBatteryBLEBatteryReader(
            targets: eligibleTargets,
            referenceDate: referenceDate
        )
        return await reader.collect()
    }

    init(
        targets: [BluetoothBatteryTarget],
        referenceDate: Date
    ) {
        self.targetsByName = Dictionary(
            uniqueKeysWithValues: targets.map { ($0.name.lowercased(), $0) }
        )
        self.referenceDate = referenceDate
        super.init()
    }

    private func collect() async -> [DeviceBatteryItem] {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
            centralManager = CBCentralManager(delegate: self, queue: .main)
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.finish()
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            finish()
            return
        }

        let connectedPeripherals = central.retrieveConnectedPeripherals(
            withServices: [Self.batteryService]
        )
        for peripheral in connectedPeripherals {
            register(peripheral, central: central)
        }

        central.scanForPeripherals(
            withServices: [Self.batteryService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        if connectedPeripherals.isEmpty {
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.finish()
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        register(peripheral, central: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        discoverServices(for: peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        pendingPeripheralIDs.remove(peripheral.identifier)
        finishIfSettled()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            pendingPeripheralIDs.remove(peripheral.identifier)
            finishIfSettled()
            return
        }

        let wantedServices = services.filter { service in
            service.uuid == Self.batteryService || service.uuid == Self.deviceInformationService
        }
        guard !wantedServices.isEmpty else {
            pendingPeripheralIDs.remove(peripheral.identifier)
            finishIfSettled()
            return
        }

        for service in wantedServices {
            peripheral.discoverCharacteristics(
                [
                    Self.batteryLevelCharacteristic,
                    Self.modelNumberCharacteristic,
                    Self.manufacturerNameCharacteristic
                ],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else {
            pendingPeripheralIDs.remove(peripheral.identifier)
            finishIfSettled()
            return
        }

        var didRead = false
        for characteristic in characteristics {
            if characteristic.uuid == Self.batteryLevelCharacteristic
                || characteristic.uuid == Self.modelNumberCharacteristic
                || characteristic.uuid == Self.manufacturerNameCharacteristic {
                didRead = true
                peripheral.readValue(for: characteristic)
            }
        }

        if !didRead, service.uuid == Self.batteryService {
            pendingPeripheralIDs.remove(peripheral.identifier)
            finishIfSettled()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        defer {
            if readingByID[peripheral.identifier]?.level != nil {
                pendingPeripheralIDs.remove(peripheral.identifier)
                finishIfSettled()
            }
        }

        guard error == nil, let value = characteristic.value else {
            return
        }

        var reading = readingByID[peripheral.identifier] ?? BluetoothBatteryReading()
        switch characteristic.uuid {
        case Self.batteryLevelCharacteristic:
            guard let level = value.first, level <= 100 else {
                return
            }
            reading.level = Int(level)
        case Self.modelNumberCharacteristic:
            reading.model = String(data: value, encoding: .utf8)
        case Self.manufacturerNameCharacteristic:
            reading.manufacturer = String(data: value, encoding: .utf8)
        default:
            return
        }
        readingByID[peripheral.identifier] = reading
    }

    private func register(_ peripheral: CBPeripheral, central: CBCentralManager) {
        guard let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              targetsByName[name.lowercased()] != nil,
              !discoveredNames.contains(name.lowercased())
        else {
            return
        }

        discoveredNames.insert(name.lowercased())
        peripheralsByID[peripheral.identifier] = peripheral
        pendingPeripheralIDs.insert(peripheral.identifier)
        peripheral.delegate = self

        if peripheral.state == .connected {
            discoverServices(for: peripheral)
        } else {
            central.connect(peripheral, options: nil)
        }
    }

    private func discoverServices(for peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService, Self.deviceInformationService])
    }

    private func finishIfSettled() {
        if !pendingPeripheralIDs.isEmpty {
            return
        }

        finish()
    }

    private func finish() {
        guard !didFinish else {
            return
        }

        didFinish = true
        timeoutTask?.cancel()
        centralManager?.stopScan()
        let items = batteryItems()
        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume(returning: items)
        }
    }

    private func batteryItems() -> [DeviceBatteryItem] {
        readingByID.compactMap { peripheralID, reading in
            guard let peripheral = peripheralsByID[peripheralID],
                  let name = peripheral.name,
                  let target = targetsByName[name.lowercased()],
                  let level = reading.level
            else {
                return nil
            }

            return DeviceBatteryItem(
                id: "corebluetooth-\(target.address ?? target.id)",
                name: target.name,
                model: firstNonEmpty(reading.model, target.model),
                kind: target.kind,
                level: level,
                chargeState: .normal,
                parentName: nil,
                source: "CoreBluetooth",
                lastUpdated: referenceDate,
                isConnected: true,
                detail: firstNonEmpty(reading.manufacturer, target.detail),
                componentIdentity: DeviceBatterySampler.componentAggregateIdentity(
                    groupID: target.componentGroupID,
                    kind: target.kind
                )
            )
        }
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
}

private struct BluetoothBatteryReading {
    var level: Int?
    var model: String?
    var manufacturer: String?
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
        "200a": "AirPods Max",
        "200b": "Powerbeats Pro",
        "200c": "Beats Solo Pro",
        "200d": "Powerbeats4",
        "200f": "AirPods 2",
        "2010": "Beats Flex",
        "2011": "Beats Studio Buds",
        "2012": "Beats Fit Pro",
        "2013": "AirPods 3",
        "2014": "AirPods Pro 2",
        "2016": "Beats Studio Buds+",
        "2017": "Beats Studio Pro",
        "2019": "AirPods 4",
        "201b": "AirPods 4",
        "201d": "AirPods Pro 2",
        "201f": "AirPods Max",
        "2024": "AirPods Pro 2",
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

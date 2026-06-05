import AppKit
import SwiftUI
import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import DeviceBatteryPlugin

@MainActor
final class DeviceBatteryPluginTests: XCTestCase {
    private let suiteName = "DeviceBatteryPluginTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPluginDescriptorUsesExpandedFullWidthSpan() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.metadata.id, "device-battery")
        XCTAssertEqual(plugin.metadata.title, "设备电量")
        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 15)!)
    }

    func testPluginDescriptorUsesExpandedSingleRowSpanForOneDevice() async throws {
        let plugin = makePlugin(items: [
            DeviceBatteryItem(
                id: "internal-battery",
                name: "MacBook 电池",
                model: nil,
                kind: .internalBattery,
                level: 82,
                chargeState: .normal,
                parentName: nil,
                source: "test",
                lastUpdated: Date(),
                isConnected: true,
                detail: nil
            )
        ])

        plugin.activate(context: makeContext())
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 6)!)

        plugin.deactivate(reason: .hostShutdown)
    }

    func testPluginDescriptorUsesExpandedSingleRowSpanForTwoDeviceList() async throws {
        let plugin = makePlugin(items: [
            makeBatteryItem(id: "mac", name: "MacBook Pro", kind: .internalBattery, level: 78),
            makeBatteryItem(id: "mouse", name: "MX Anywhere 3S", kind: .bluetooth, level: 85)
        ])

        plugin.activate(context: makeContext())
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 11)!)

        plugin.deactivate(reason: .hostShutdown)
    }

    func testPluginDescriptorGrowsListSpanWithVisibleDeviceCount() async throws {
        let plugin = makePlugin(items: [
            makeBatteryItem(id: "mac", name: "MacBook Pro", kind: .internalBattery, level: 78),
            makeBatteryItem(id: "mouse", name: "MX Anywhere 3S", kind: .bluetooth, level: 85),
            makeBatteryItem(id: "keyboard", name: "Magic Keyboard", kind: .magicAccessory, level: 72),
            makeBatteryItem(id: "trackpad", name: "Magic Trackpad", kind: .magicAccessory, level: 64),
            makeBatteryItem(id: "headphones", name: "Beats Fit Pro", kind: .bluetooth, level: 51)
        ])

        plugin.activate(context: makeContext())
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 24)!)

        plugin.deactivate(reason: .hostShutdown)
    }

    func testGaugeLayoutSpanAccountsForOverflowCell() {
        XCTAssertEqual(
            DeviceBatteryComponentLayout.spanHeight(mode: .list, visibleItemCount: 9),
            31
        )
    }

    func testGaugeLayoutSpanSupportsSingleDevice() {
        XCTAssertEqual(
            DeviceBatteryComponentLayout.spanHeight(mode: .list, visibleItemCount: 1),
            14
        )
    }

    func testPluginHostIncludesComponentAndConfiguration() {
        let plugin = makePlugin()
        let host = makePluginHostForTests(
            plugins: [plugin],
            suiteName: suiteName
        )

        XCTAssertTrue(host.componentItems.contains { $0.id == "device-battery" })
        XCTAssertFalse(host.panelItems.contains { $0.id == "device-battery" })
        XCTAssertEqual(
            host.featureManagementItems.first { $0.id == "device-battery" }?.presentation,
            .componentPanel
        )
        XCTAssertTrue(host.pluginConfigurationItems.contains { $0.id == "device-battery" })
    }

    func testPluginHostUsesPermissionCardForInputMonitoring() {
        let plugin = makePlugin(inputMonitoringAuthorizationStatus: .unknown)
        let host = makePluginHostForTests(
            plugins: [plugin],
            suiteName: suiteName
        )

        let item = host.pluginConfigurationItems.first { $0.id == "device-battery" }
        XCTAssertEqual(
            item?.description,
            pluginL10n.string("configuration.description", defaultValue: "选择组件面板布局和显示内容。")
        )
        XCTAssertEqual(item?.settingsCards.map(\.id), [])
        XCTAssertEqual(
            item?.permissionCards.map(\.title),
            [pluginL10n.string("permission.inputMonitoring.title", defaultValue: "输入监控授权")]
        )
        XCTAssertEqual(
            item?.permissionCards.first?.description,
            pluginL10n.string(
                "permission.inputMonitoring.description",
                defaultValue: "用于读取已适配厂商 HID 鼠标的电量、充电状态、设备型号和名称。"
            )
        )
        XCTAssertEqual(
            item?.permissionCards.first?.statusText,
            AppL10n.plugins("plugin.permission.notGranted", defaultValue: "未授权")
        )
    }

    func testInputMonitoringPermissionCardShowsAuthorizedWhenGranted() {
        let rapooMonitor = StubRapooBatteryMonitor()
        rapooMonitor.emit(
            RapooMouseBatterySnapshot(
                accessState: .connected,
                device: RapooMouseDeviceInfo(
                    productID: 5139,
                    modelName: "VT7",
                    displayName: "VT7",
                    serialNumber: nil,
                    locationID: nil
                ),
                reading: RapooBatteryReading(level: 76, chargeState: .normal, statusCode: 0),
                lastUpdated: Date()
            )
        )
        let plugin = makePlugin(
            rapooMonitor: rapooMonitor,
            inputMonitoringAuthorizationStatus: .granted
        )
        let host = makePluginHostForTests(
            plugins: [plugin],
            suiteName: suiteName
        )

        let item = host.pluginConfigurationItems.first { $0.id == "device-battery" }
        XCTAssertEqual(
            item?.permissionCards.first?.statusText,
            AppL10n.plugins("plugin.permission.granted", defaultValue: "已授权")
        )
    }

    func testInputMonitoringPermissionCardShowsUnauthorizedWhenDenied() {
        let plugin = makePlugin(inputMonitoringAuthorizationStatus: .denied)
        let host = makePluginHostForTests(
            plugins: [plugin],
            suiteName: suiteName
        )

        let item = host.pluginConfigurationItems.first { $0.id == "device-battery" }
        XCTAssertEqual(
            item?.permissionCards.first?.statusText,
            AppL10n.plugins("plugin.permission.notGranted", defaultValue: "未授权")
        )
    }

    func testStorePersistsLayoutAndSources() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let storage = UserDefaultsPluginStorage(pluginID: "device-battery", userDefaults: defaults)
        let store = DeviceBatteryStore(storage: storage)

        store.setLayoutMode(.list)
        store.setShowBluetoothDevices(false)
        store.setShowRapooDevices(false)

        let reloaded = DeviceBatteryStore(storage: storage)
        XCTAssertEqual(reloaded.layoutMode, .list)
        XCTAssertTrue(reloaded.showInternalBattery)
        XCTAssertFalse(reloaded.showBluetoothDevices)
        XCTAssertFalse(reloaded.showRapooDevices)
    }

    func testBluetoothPowerLogParserReadsConnectedMouseBattery() {
        let line = """
        2026-06-02 14:05:52.648 Df bluetoothd[616:f85de1] [com.apple.bluetooth:CBPowerSource] Power source updated CBPowerSource Nm 'MX Anywhere 3S', SID 49354549, AcCa Mouse, AcID 0532E370-EA18-11C7-44F9-6D7E86E35891, PID 0xB037 (?), VID 0x046D (?), VIDSrc USB, Type 'Accessory Source', TPT Bluetooth LE, CF 0x1 < Attributes >, IF 0x2 < IOKit >, Present yes, MaxC 100%, Battery -80%
        """

        let reading = DeviceBatteryBluetoothPowerLogParser.reading(from: line)

        XCTAssertEqual(reading?.name, "MX Anywhere 3S")
        XCTAssertEqual(reading?.vendorID, "0x046D")
        XCTAssertEqual(reading?.productID, "0xB037")
        XCTAssertEqual(reading?.deviceType, "Mouse")
        XCTAssertEqual(reading?.level, 80)
        XCTAssertEqual(reading?.chargeState, .normal)
    }

    func testBluetoothPowerLogParserReadsChargingSign() {
        let line = """
        2026-06-02 14:05:52.648 Df bluetoothd[616:f85de1] [com.apple.bluetooth:CBPowerSource] Power source updated CBPowerSource Nm 'Charging Mouse', AcCa Mouse, PID 0xB037 (?), VID 0x046D (?), Battery +75%
        """

        let reading = DeviceBatteryBluetoothPowerLogParser.reading(from: line)

        XCTAssertEqual(reading?.level, 75)
        XCTAssertEqual(reading?.chargeState, .charging)
    }

    func testBluetoothPowerLogParserReadsAirPodsComponentChargingState() {
        let line = """
        2026-06-02 16:43:44.978 Df bluetoothd[616:ff000b] [com.apple.bluetooth:CBPowerSource] Power source updated CBPowerSource Nm 'ggbond AirPods 4', SID 70391692, AcCa Headphone, PID 0x201B (Device1,8219), VID 0x004C (Apple), Battery 68% (Unknown), Components (Y): Left +100%, CF 0x1 < Attributes >, Right +100%, CF 0x1 < Attributes >, Case +83%, CF 0x1 < Attributes >
        """

        let readings = DeviceBatteryBluetoothPowerLogParser.readings(fromLine: line)
        let caseReading = readings.first { $0.component == .chargingCase }
        let leftReading = readings.first { $0.component == .left }
        let mainReading = readings.first { $0.component == nil }

        XCTAssertEqual(mainReading?.level, 68)
        XCTAssertEqual(mainReading?.chargeState, .normal)
        XCTAssertEqual(leftReading?.level, 100)
        XCTAssertEqual(leftReading?.chargeState, .charging)
        XCTAssertEqual(caseReading?.level, 83)
        XCTAssertEqual(caseReading?.chargeState, .charging)
    }

    func testBluetoothPowerLogParserKeepsLatestReadingForSameDevice() {
        let output = """
        2026-06-02 14:04:52.648 Df bluetoothd[616:f85de1] [com.apple.bluetooth:CBPowerSource] Power source updated CBPowerSource Nm 'MX Anywhere 3S', AcCa Mouse, PID 0xB037 (?), VID 0x046D (?), Battery -81%
        2026-06-02 14:05:52.648 Df bluetoothd[616:f85de1] [com.apple.bluetooth:CBPowerSource] Power source updated CBPowerSource Nm 'MX Anywhere 3S', AcCa Mouse, PID 0xB037 (?), VID 0x046D (?), Battery -80%
        """

        let readings = DeviceBatteryBluetoothPowerLogParser.readings(from: output)

        XCTAssertEqual(readings.count, 1)
        XCTAssertEqual(readings.first?.level, 80)
    }

    func testBluetoothPowerLogFilterMatchesConnectedMouseLine() {
        let line = """
        2026-06-02 14:05:52.648 Df bluetoothd[616:f85de1] [com.apple.bluetooth:CBPowerSource] Power source updated CBPowerSource Nm 'MX Anywhere 3S', AcCa Mouse, PID 0xB037 (?), VID 0x046D (?), Battery -80%
        """

        XCTAssertTrue(DeviceBatterySampler.isBluetoothPowerLogLine(
            line,
            matchingName: "MX Anywhere 3S",
            vendorID: "0x046D",
            productID: "0xB037"
        ))
    }

    func testBluetoothPowerLogFilterRequiresVendorAndProductWhenNameDiffers() {
        let line = """
        2026-06-02 14:05:52.648 Df bluetoothd[616:f85de1] [com.apple.bluetooth:CBPowerSource] Power source updated CBPowerSource Nm 'Other Logitech Mouse', AcCa Mouse, PID 0xC548 (?), VID 0x046D (?), Battery -80%
        """

        XCTAssertFalse(DeviceBatterySampler.isBluetoothPowerLogLine(
            line,
            matchingName: "MX Anywhere 3S",
            vendorID: "0x046D",
            productID: "0xB037"
        ))
    }

    func testSystemProfilerKeepsDisconnectedAirPodsWhenBatteryFieldsExist() {
        let output = """
        {
          "SPBluetoothDataType": [
            {
              "device_connected": [
                {
                  "MX Anywhere 3S": {
                    "device_address": "D6:82:90:EE:D6:0F",
                    "device_minorType": "Mouse",
                    "device_productID": "0xB037",
                    "device_vendorID": "0x046D"
                  }
                }
              ],
              "device_not_connected": [
                {
                  "ggbond AirPods 4": {
                    "device_address": "C4:B3:49:EE:7F:62",
                    "device_batteryLevelMain": "68%",
                    "device_batteryLevelCase": "80%",
                    "device_batteryLevelLeft": "100%",
                    "device_batteryLevelRight": "100%",
                    "device_minorType": "Headphones",
                    "device_productID": "0x201B",
                    "device_vendorID": "0x004C"
                  }
                }
              ]
            }
          ]
        }
        """

        let items = DeviceBatterySampler.bluetoothProfileBatteryItems(
            fromSystemProfilerOutput: output,
            referenceDate: Date()
        )
        let caseItem = items.first { $0.name == "ggbond AirPods 4 充电盒" }

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(caseItem?.level, 80)
        XCTAssertEqual(caseItem?.model, "AirPods 4")
        XCTAssertFalse(caseItem?.isConnected ?? true)
        XCTAssertFalse(items.contains { $0.name == "ggbond AirPods 4" })
        XCTAssertFalse(items.contains { $0.name == "MX Anywhere 3S" })
    }

    func testBluetoothKindKeepsConnectedMouseAsBluetoothDevice() {
        XCTAssertEqual(
            DeviceBatterySampler.inferredBluetoothKind(
                name: "MX Anywhere 3S",
                minorType: "Mouse",
                vendorID: "0x046D",
                field: "single"
            ),
            .bluetooth
        )
    }

    func testBluetoothMouseUsesMouseSymbol() {
        let item = makeBatteryItem(
            id: "mx-anywhere",
            name: "MX Anywhere 3S",
            kind: .bluetooth,
            level: 80
        )

        XCTAssertEqual(deviceSymbolName(for: item), "computermouse.fill")
    }

    func testViewModelPrefersChargingStateWhenDuplicateSourcesExist() async throws {
        let date = Date()
        let normalCase = DeviceBatteryItem(
            id: "system-profiler-airpods-case",
            name: "ggbond AirPods 4 充电盒",
            model: "AirPods 4",
            kind: .airPodsPart,
            level: 82,
            chargeState: .normal,
            parentName: "ggbond AirPods 4",
            source: "system_profiler",
            lastUpdated: date,
            isConnected: true,
            detail: "Headphones"
        )
        let chargingCase = DeviceBatteryItem(
            id: "powerlog-airpods-case",
            name: "ggbond AirPods 4 充电盒",
            model: "AirPods 4",
            kind: .airPodsPart,
            level: 83,
            chargeState: .charging,
            parentName: "ggbond AirPods 4",
            source: "BluetoothPowerLog",
            lastUpdated: date,
            isConnected: true,
            detail: "Headphones"
        )

        let viewModel = DeviceBatteryViewModel(
            sampler: StubDeviceBatterySampler(items: [normalCase, chargingCase]),
            rapooMonitor: StubRapooBatteryMonitor()
        )
        viewModel.start(
            includeInternalBattery: true,
            includeBluetoothDevices: true,
            includeRapooDevices: false
        )

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.visibleItems.count, 1)
        XCTAssertEqual(viewModel.snapshot.visibleItems.first?.level, 83)
        XCTAssertEqual(viewModel.snapshot.visibleItems.first?.chargeState, .charging)
        viewModel.stop()
    }

    func testViewModelDropsAirPodsAggregateWhenComponentsExist() async throws {
        let date = Date()
        let aggregate = makeAirPodsItem(
            id: "airpods-main",
            name: "ggbond AirPods 4",
            level: 68,
            parentName: nil,
            componentRole: .aggregate,
            date: date
        )
        let caseItem = makeAirPodsItem(
            id: "airpods-case",
            name: "ggbond AirPods 4 充电盒",
            level: 83,
            parentName: "ggbond AirPods 4",
            componentRole: .chargingCase,
            date: date
        )
        let leftItem = makeAirPodsItem(
            id: "airpods-left",
            name: "ggbond AirPods 4 左耳",
            level: 100,
            parentName: "ggbond AirPods 4 充电盒",
            componentRole: .left,
            date: date
        )
        let rightItem = makeAirPodsItem(
            id: "airpods-right",
            name: "ggbond AirPods 4 右耳",
            level: 100,
            parentName: "ggbond AirPods 4 充电盒",
            componentRole: .right,
            date: date
        )

        let viewModel = DeviceBatteryViewModel(
            sampler: StubDeviceBatterySampler(items: [aggregate, caseItem, leftItem, rightItem]),
            rapooMonitor: StubRapooBatteryMonitor()
        )
        viewModel.start(
            includeInternalBattery: true,
            includeBluetoothDevices: true,
            includeRapooDevices: false
        )

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.visibleItems.count, 3)
        XCTAssertFalse(viewModel.snapshot.visibleItems.contains { $0.name == "ggbond AirPods 4" })
        XCTAssertTrue(viewModel.snapshot.visibleItems.contains { $0.name == "ggbond AirPods 4 充电盒" })
        XCTAssertTrue(viewModel.snapshot.visibleItems.contains { $0.name == "ggbond AirPods 4 左耳" })
        XCTAssertTrue(viewModel.snapshot.visibleItems.contains { $0.name == "ggbond AirPods 4 右耳" })
        viewModel.stop()
    }

    func testViewModelKeepsAirPodsAggregateWhenNoComponentsExist() async throws {
        let aggregate = makeAirPodsItem(
            id: "airpods-main",
            name: "ggbond AirPods 4",
            level: 68,
            parentName: nil,
            componentRole: .aggregate,
            date: Date()
        )

        let viewModel = DeviceBatteryViewModel(
            sampler: StubDeviceBatterySampler(items: [aggregate]),
            rapooMonitor: StubRapooBatteryMonitor()
        )
        viewModel.start(
            includeInternalBattery: true,
            includeBluetoothDevices: true,
            includeRapooDevices: false
        )

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.visibleItems.map(\.name), ["ggbond AirPods 4"])
        viewModel.stop()
    }

    func testViewModelMergesSystemAndRapooItems() async throws {
        let sampler = StubDeviceBatterySampler(items: [
            DeviceBatteryItem(
                id: "internal-battery",
                name: "MacBook 电池",
                model: nil,
                kind: .internalBattery,
                level: 82,
                chargeState: .normal,
                parentName: nil,
                source: "test",
                lastUpdated: Date(),
                isConnected: true,
                detail: nil
            )
        ])
        let rapooMonitor = StubRapooBatteryMonitor()
        let viewModel = DeviceBatteryViewModel(sampler: sampler, rapooMonitor: rapooMonitor)
        viewModel.start(
            includeInternalBattery: true,
            includeBluetoothDevices: true,
            includeRapooDevices: true
        )
        rapooMonitor.emit(
            RapooMouseBatterySnapshot(
                accessState: .connected,
                device: RapooMouseDeviceInfo(
                    productID: 5139,
                    modelName: "VT7",
                    displayName: "Rapoo Gaming Device",
                    serialNumber: "2507-54L",
                    locationID: 1
                ),
                reading: RapooBatteryReading(level: 76, chargeState: .normal, statusCode: 1),
                lastUpdated: Date()
            )
        )

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(viewModel.snapshot.visibleItems.count, 2)
        XCTAssertTrue(viewModel.snapshot.visibleItems.contains { $0.kind == .rapooMouse && $0.level == 76 })
        XCTAssertEqual(viewModel.snapshot.accessState, .ready)
    }

    func testRapooParserReadsProtocolOneBatteryReport() {
        let report = [UInt8](repeating: 0, count: 16).setting(1, at: 6).setting(83, at: 7)
        let reading = RapooBatteryParser.parseInputReport(reportID: 7, bytes: report)

        XCTAssertEqual(reading, RapooBatteryReading(level: 83, chargeState: .normal, statusCode: 1))
    }

    func testRapooParserReadsChargingState() {
        let report = [UInt8](repeating: 0, count: 16).setting(2, at: 6).setting(45, at: 7)
        let reading = RapooBatteryParser.parseInputReport(reportID: 7, bytes: report)

        XCTAssertEqual(reading, RapooBatteryReading(level: 45, chargeState: .charging, statusCode: 2))
    }

    func testRapooParserUsesSecondCandidateWhenFirstCandidateIsInvalid() {
        let report = [UInt8](repeating: 0, count: 16).setting(1, at: 7).setting(64, at: 8)
        let reading = RapooBatteryParser.parseInputReport(reportID: 7, bytes: report)

        XCTAssertEqual(reading, RapooBatteryReading(level: 64, chargeState: .normal, statusCode: 1))
    }

    func testRapooParserRejectsUnexpectedReportID() {
        let report = [UInt8](repeating: 0, count: 16).setting(1, at: 6).setting(83, at: 7)

        XCTAssertNil(RapooBatteryParser.parseInputReport(reportID: 9, bytes: report))
    }

    func testRapooParserRejectsOutOfRangeLevel() {
        let report = [UInt8](repeating: 0, count: 16).setting(1, at: 6).setting(130, at: 7)

        XCTAssertNil(RapooBatteryParser.parseInputReport(reportID: 7, bytes: report))
    }

    func testRapooCatalogUsesDocumentedHIDIdentifiers() {
        XCTAssertEqual(RapooDeviceCatalog.vendorID, 0x24AE)
        XCTAssertEqual(RapooDeviceCatalog.vendorUsagePage, 0xFF00)
        XCTAssertEqual(RapooDeviceCatalog.vendorUsage, 0x0001)
        XCTAssertEqual(RapooDeviceCatalog.inputReportID, 7)
        XCTAssertEqual(RapooDeviceCatalog.featureReportID, 8)
        XCTAssertEqual(RapooDeviceCatalog.reportLength, 512)
    }

    func testRapooCatalogMapsReceiverProductIDToVT7() {
        XCTAssertEqual(RapooDeviceCatalog.modelName(forProductID: 5139), "VT7")
        XCTAssertEqual(RapooDeviceCatalog.modelName(forProductID: 17939), "VT7")
        XCTAssertTrue(RapooDeviceCatalog.isSupportedMouseProductID(5139))
    }

    func testAirPodsPartSymbolsUseOwnPartNameInsteadOfParentCaseName() {
        let caseItem = makeAirPodsPart(name: "AirPods Pro 2 充电盒", parentName: "AirPods Pro 2")
        let leftItem = makeAirPodsPart(name: "AirPods Pro 2 左耳", parentName: "AirPods Pro 2 充电盒")
        let rightItem = makeAirPodsPart(name: "AirPods Pro 2 右耳", parentName: "AirPods Pro 2 充电盒")

        XCTAssertEqual(deviceSymbolName(for: caseItem), "airpodspro.chargingcase.wireless")
        XCTAssertEqual(deviceSymbolName(for: leftItem), "airpodpro.left")
        XCTAssertEqual(deviceSymbolName(for: rightItem), "airpodpro.right")
    }

    func testAirPodsPartSymbolsKeepNonProShape() {
        let caseItem = makeAirPodsPart(name: "AirPods 充电盒", parentName: "AirPods")
        let leftItem = makeAirPodsPart(name: "AirPods 左耳", parentName: "AirPods 充电盒")
        let rightItem = makeAirPodsPart(name: "AirPods 右耳", parentName: "AirPods 充电盒")

        XCTAssertEqual(deviceSymbolName(for: caseItem), "airpods.chargingcase")
        XCTAssertEqual(deviceSymbolName(for: leftItem), "airpod.left")
        XCTAssertEqual(deviceSymbolName(for: rightItem), "airpod.right")
    }

    func testAirPodsGenerationSymbolsPreferNativeShapes() {
        let gen4Item = makeAirPodsPart(name: "AirPods 4", parentName: nil)
        let gen4LeftItem = makeAirPodsPart(name: "AirPods 4 左耳", parentName: "AirPods 4 充电盒")
        let gen4CaseItem = makeAirPodsPart(name: "AirPods 4 充电盒", parentName: "AirPods 4")
        let gen3LeftItem = makeAirPodsPart(name: "AirPods 3 左耳", parentName: "AirPods 3 充电盒")

        XCTAssertEqual(deviceSymbolName(for: gen4Item), expectedAvailableSymbol(["airpods.gen4", "airpods"]))
        XCTAssertEqual(deviceSymbolName(for: gen4LeftItem), expectedAvailableSymbol(["airpods.gen4.left", "airpod.left"]))
        XCTAssertEqual(deviceSymbolName(for: gen4CaseItem), expectedAvailableSymbol(["airpods.gen4.chargingcase.wireless", "airpods.chargingcase"]))
        XCTAssertEqual(deviceSymbolName(for: gen3LeftItem), expectedAvailableSymbol(["airpod.gen3.left", "airpod.left"]))
    }

    func testBluetoothDeviceSymbolsMatchCommonMinorTypes() {
        XCTAssertEqual(
            deviceSymbolName(for: makeBatteryItem(id: "keyboard", name: "HHKB-Hybrid_1", kind: .bluetooth, level: 70, detail: "Keyboard")),
            "keyboard.fill"
        )
        XCTAssertEqual(
            deviceSymbolName(for: makeBatteryItem(id: "trackpad", name: "Magic Trackpad", kind: .magicAccessory, level: 70, detail: "Trackpad")),
            "rectangle.and.hand.point.up.left.fill"
        )
        XCTAssertEqual(
            deviceSymbolName(for: makeBatteryItem(id: "headset", name: "realme Buds Air 3", kind: .bluetooth, level: 70, detail: "Headset")),
            "headphones"
        )
        XCTAssertEqual(
            deviceSymbolName(for: makeBatteryItem(id: "speaker", name: "Living Room Speaker", kind: .bluetooth, level: 70, detail: "Speaker")),
            "hifispeaker.fill"
        )
        XCTAssertEqual(
            deviceSymbolName(for: makeBatteryItem(id: "controller", name: "Xbox Wireless Controller", kind: .bluetooth, level: 70, detail: "Gamepad")),
            "gamecontroller.fill"
        )
    }

    func testBluetoothDeviceSymbolsFallbackToKindIcon() {
        let item = makeBatteryItem(
            id: "unknown",
            name: "Unknown Accessory",
            kind: .bluetooth,
            level: 70,
            detail: "Accessory"
        )

        XCTAssertEqual(deviceSymbolName(for: item), DeviceBatteryKind.bluetooth.iconName)
    }

    private func makePlugin(
        items: [DeviceBatteryItem] = [],
        rapooMonitor: StubRapooBatteryMonitor? = nil,
        inputMonitoringAuthorizationStatus: DeviceBatteryInputMonitoringAuthorizationStatus = .unknown
    ) -> DeviceBatteryPlugin {
        DeviceBatteryPlugin(
            context: makeContext(),
            viewModel: DeviceBatteryViewModel(
                sampler: StubDeviceBatterySampler(items: items),
                rapooMonitor: rapooMonitor ?? StubRapooBatteryMonitor()
            ),
            inputMonitoringAuthorizationStatus: { inputMonitoringAuthorizationStatus }
        )
    }

    private var pluginL10n: PluginLocalization {
        PluginLocalization(bundle: .main)
    }

    private func makeContext() -> PluginRuntimeContext {
        let defaults = UserDefaults(suiteName: suiteName)!
        return PluginRuntimeContext(
            pluginID: "device-battery",
            storage: UserDefaultsPluginStorage(pluginID: "device-battery", userDefaults: defaults)
        )
    }

    private func makeAirPodsPart(name: String, parentName: String?) -> DeviceBatteryItem {
        DeviceBatteryItem(
            id: name,
            name: name,
            model: nil,
            kind: .airPodsPart,
            level: 88,
            chargeState: .normal,
            parentName: parentName,
            source: "test",
            lastUpdated: Date(),
            isConnected: true,
            detail: nil
        )
    }

    private func makeAirPodsItem(
        id: String,
        name: String,
        level: Int,
        parentName: String?,
        componentRole: DeviceBatteryComponentRole,
        date: Date
    ) -> DeviceBatteryItem {
        DeviceBatteryItem(
            id: id,
            name: name,
            model: "AirPods 4",
            kind: .airPodsPart,
            level: level,
            chargeState: .normal,
            parentName: parentName,
            source: "test",
            lastUpdated: date,
            isConnected: true,
            detail: "Headphones",
            componentIdentity: DeviceBatteryComponentIdentity(
                groupID: "airpods-group",
                role: componentRole
            )
        )
    }

    private func expectedAvailableSymbol(_ candidates: [String]) -> String {
        for candidate in candidates {
            if NSImage(systemSymbolName: candidate, accessibilityDescription: nil) != nil {
                return candidate
            }
        }

        return candidates.last!
    }

    private func makeBatteryItem(
        id: String,
        name: String,
        kind: DeviceBatteryKind,
        level: Int,
        detail: String? = nil
    ) -> DeviceBatteryItem {
        DeviceBatteryItem(
            id: id,
            name: name,
            model: nil,
            kind: kind,
            level: level,
            chargeState: .normal,
            parentName: nil,
            source: "test",
            lastUpdated: Date(),
            isConnected: true,
            detail: detail
        )
    }
}

private struct StubDeviceBatterySampler: DeviceBatterySampling {
    let items: [DeviceBatteryItem]

    func collectSystemDevices(referenceDate: Date) async -> [DeviceBatteryItem] {
        items
    }
}

@MainActor
private final class StubRapooBatteryMonitor: RapooBatteryMonitoring {
    private(set) var snapshot = RapooMouseBatterySnapshot.idle
    var onSnapshotChange: ((RapooMouseBatterySnapshot) -> Void)?

    func start() {
        onSnapshotChange?(snapshot)
    }

    func stop() {}

    func refresh() {
        onSnapshotChange?(snapshot)
    }

    func emit(_ snapshot: RapooMouseBatterySnapshot) {
        self.snapshot = snapshot
        onSnapshotChange?(snapshot)
    }
}

private extension Array where Element == UInt8 {
    func setting(_ value: UInt8, at index: Int) -> [UInt8] {
        var copy = self
        copy[index] = value
        return copy
    }
}

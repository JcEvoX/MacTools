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

    func testPluginDescriptorUsesFourByTwoSpan() {
        let plugin = makePlugin()

        XCTAssertEqual(plugin.metadata.id, "device-battery")
        XCTAssertEqual(plugin.metadata.title, "设备电量")
        XCTAssertEqual(plugin.descriptor.span, .fourByTwo)
    }

    func testPluginDescriptorUsesSingleRowSpanForOneDevice() async throws {
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

        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 1)!)

        plugin.deactivate(reason: .hostShutdown)
    }

    func testPluginDescriptorUsesSingleRowSpanForTwoDeviceList() async throws {
        let plugin = makePlugin(items: [
            makeBatteryItem(id: "mac", name: "MacBook Pro", kind: .internalBattery, level: 78),
            makeBatteryItem(id: "mouse", name: "MX Anywhere 3S", kind: .bluetooth, level: 85)
        ])

        plugin.activate(context: makeContext())
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 1)!)

        plugin.deactivate(reason: .hostShutdown)
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

    func testStorePersistsLayoutAndSources() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let storage = UserDefaultsPluginStorage(pluginID: "device-battery", userDefaults: defaults)
        let store = DeviceBatteryStore(storage: storage)

        store.setLayoutMode(.showcase)
        store.setShowBluetoothDevices(false)
        store.setShowRapooDevices(false)

        let reloaded = DeviceBatteryStore(storage: storage)
        XCTAssertEqual(reloaded.layoutMode, .showcase)
        XCTAssertTrue(reloaded.showInternalBattery)
        XCTAssertFalse(reloaded.showBluetoothDevices)
        XCTAssertFalse(reloaded.showRapooDevices)
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

    private func makePlugin(items: [DeviceBatteryItem] = []) -> DeviceBatteryPlugin {
        DeviceBatteryPlugin(
            context: makeContext(),
            viewModel: DeviceBatteryViewModel(
                sampler: StubDeviceBatterySampler(items: items),
                rapooMonitor: StubRapooBatteryMonitor()
            )
        )
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

    private func makeBatteryItem(
        id: String,
        name: String,
        kind: DeviceBatteryKind,
        level: Int
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
            detail: nil
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

import SwiftUI
import XCTest
import MacToolsPluginKit
@testable import MacTools
@testable import SystemStatusPlugin

@MainActor
final class SystemStatusPluginTests: XCTestCase {
    private let suiteName = "SystemStatusPluginTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPluginDescriptorUsesExpandedFullWidthSpan() {
        let plugin = SystemStatusPlugin()

        XCTAssertEqual(plugin.metadata.id, "system-status")
        XCTAssertEqual(plugin.metadata.title, "系统状态")
        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 25)!)
    }

    func testPluginHostIncludesSystemStatusComponentOnlyWhenProvided() {
        let host = makePluginHostForTests(
            plugins: [SystemStatusPlugin()],
            suiteName: suiteName
        )

        XCTAssertTrue(host.componentItems.contains { $0.id == "system-status" })
        XCTAssertFalse(host.panelItems.contains { $0.id == "system-status" })

        let managementItem = host.featureManagementItems.first { $0.id == "system-status" }
        XCTAssertEqual(managementItem?.presentation, .componentPanel)
    }

    func testSystemStatusLayoutUsesFourColumnTwoRowOrder() {
        XCTAssertEqual(SystemStatusComponentLayout.columns, 4)
        XCTAssertEqual(SystemStatusComponentLayout.rows, 2)
        XCTAssertEqual(SystemStatusComponentLayout.cardSpacing, 6)
        XCTAssertEqual(SystemStatusComponentLayout.cardContentPadding, 6)
        XCTAssertEqual(
            SystemStatusComponentLayout.orderedMetricKinds,
            [.cpu, .memory, .disk, .battery, .network, .topProcesses]
        )
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .cpu), SystemStatusGridPosition(row: 0, column: 0))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .memory), SystemStatusGridPosition(row: 0, column: 1))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .disk), SystemStatusGridPosition(row: 0, column: 2))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .battery), SystemStatusGridPosition(row: 0, column: 3))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .network), SystemStatusGridPosition(row: 1, column: 0))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .topProcesses), SystemStatusGridPosition(row: 1, column: 2))
    }

    func testViewModelKeepsLastSnapshotAfterStop() async throws {
        let sampler = StubSystemStatusSampler()
        let viewModel = SystemStatusViewModel(sampler: sampler)

        viewModel.start()
        try await Task.sleep(for: .milliseconds(40))
        viewModel.stop()

        let cachedSnapshot = viewModel.snapshot
        XCTAssertNotEqual(cachedSnapshot, .empty)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.snapshot, cachedSnapshot)
        let counts = await sampler.callCounts
        XCTAssertGreaterThan(counts.fast, 0)
        XCTAssertGreaterThan(counts.slow, 0)
        XCTAssertGreaterThan(counts.processes, 0)
    }

    func testPluginReusesViewModelAcrossComponentViews() {
        let viewModel = SystemStatusViewModel(sampler: StubSystemStatusSampler())
        let plugin = SystemStatusPlugin(viewModel: viewModel)

        let first = plugin.makeView(
            context: PluginComponentContext(
                pluginID: "system-status",
                dismiss: {},
                isPanelVisible: true
            )
        )
        let second = plugin.makeView(
            context: PluginComponentContext(
                pluginID: "system-status",
                dismiss: {},
                isPanelVisible: true
            )
        )

        XCTAssertFalse(String(describing: first).isEmpty)
        XCTAssertFalse(String(describing: second).isEmpty)
    }
}

private actor StubSystemStatusSampler: SystemStatusSampling {
    private(set) var fastCallCount = 0
    private(set) var slowCallCount = 0
    private(set) var processCallCount = 0
    private(set) var publicIPCallCount = 0

    var callCounts: (fast: Int, slow: Int, processes: Int, publicIP: Int) {
        (fastCallCount, slowCallCount, processCallCount, publicIPCallCount)
    }

    func collectFast(referenceDate: Date) async -> SystemStatusFastSample {
        fastCallCount += 1
        return SystemStatusFastSample(
            cpu: SystemStatusCPUSnapshot(
                usage: 0.25,
                temperatureCelsius: 42,
                systemPowerWatts: 8.5,
                isCollecting: false
            ),
            memory: SystemStatusMemorySnapshot(
                usedBytes: 4_000,
                totalBytes: 8_000
            ),
            network: SystemStatusNetworkSnapshot(
                interfaceName: "en0",
                ipAddress: "192.168.1.2",
                publicIPAddress: nil,
                downloadBytesPerSecond: 1_024,
                uploadBytesPerSecond: 512,
                isConnected: true,
                isCollecting: false
            )
        )
    }

    func collectSlow() async -> SystemStatusSlowSample {
        slowCallCount += 1
        return SystemStatusSlowSample(
            disk: SystemStatusDiskSnapshot(
                usedBytes: 50,
                totalBytes: 100
            ),
            battery: SystemStatusBatterySnapshot(
                isAvailable: true,
                level: 0.8,
                state: .acPower,
                timeRemainingMinutes: nil,
                adapterWatts: 70,
                temperatureCelsius: 31,
                healthPercent: 96
            )
        )
    }

    func collectTopProcesses(limit: Int) async -> [SystemStatusTopProcess] {
        processCallCount += 1
        return [
            SystemStatusTopProcess(
                pid: 1,
                displayName: "launchd",
                command: "/sbin/launchd",
                cpuPercent: 1,
                memoryPercent: 0.1
            )
        ]
    }

    func collectPublicIPAddress() async -> String? {
        publicIPCallCount += 1
        return "203.0.113.1"
    }
}

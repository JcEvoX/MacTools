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
        let expectedHeight = PluginComponentPanelLayoutMetrics.default.heightSpan(
            fittingContentHeight: SystemStatusComponentLayout.dashboardContentHeight
        )

        XCTAssertEqual(plugin.metadata.id, "system-status")
        XCTAssertEqual(plugin.metadata.title, "系统状态")
        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: expectedHeight)!)
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

    func testSystemStatusLayoutUsesTwoColumnCoreMetricGridOrder() {
        XCTAssertEqual(SystemStatusComponentLayout.columns, 2)
        XCTAssertEqual(SystemStatusComponentLayout.rows, 3)
        XCTAssertEqual(SystemStatusComponentLayout.cardSpacing, 6)
        XCTAssertEqual(SystemStatusComponentLayout.cardContentPadding, 8)
        XCTAssertEqual(SystemStatusComponentLayout.dashboardContentHeight, 411)
        XCTAssertEqual(
            SystemStatusComponentLayout.orderedMetricKinds,
            [.cpu, .gpu, .memory, .network, .disk, .battery]
        )
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .cpu), SystemStatusGridPosition(row: 0, column: 0))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .gpu), SystemStatusGridPosition(row: 0, column: 1))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .memory), SystemStatusGridPosition(row: 1, column: 0))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .network), SystemStatusGridPosition(row: 1, column: 1))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .disk), SystemStatusGridPosition(row: 2, column: 0))
        XCTAssertEqual(SystemStatusComponentLayout.position(for: .battery), SystemStatusGridPosition(row: 2, column: 1))
        XCTAssertNil(SystemStatusComponentLayout.position(for: .topProcesses))
    }

    func testProductionSamplingScheduleBalancesForegroundDetailAndBackgroundCost() {
        let schedule = SystemStatusSamplingSchedule.production

        XCTAssertEqual(schedule.backgroundFastInterval, .seconds(10))
        XCTAssertEqual(schedule.foregroundFastInterval, .seconds(1))
        XCTAssertEqual(schedule.backgroundSlowInterval, 30)
        XCTAssertEqual(schedule.foregroundSlowInterval, 5)
        XCTAssertEqual(schedule.backgroundProcessInterval, 60)
        XCTAssertEqual(schedule.foregroundProcessInterval, 5)
        XCTAssertEqual(schedule.backgroundHistoryInterval, 60)
        XCTAssertEqual(schedule.foregroundHistoryInterval, 60)
    }

    func testViewModelKeepsLastSnapshotAfterStop() async throws {
        let sampler = StubSystemStatusSampler()
        let historyStore = StubSystemStatusHistoryStore()
        let viewModel = SystemStatusViewModel(
            sampler: sampler,
            historyStore: historyStore,
            schedule: .test
        )

        await viewModel.refreshSnapshotNow(referenceDate: Date(timeIntervalSince1970: 1_000))
        viewModel.stop()

        let cachedSnapshot = viewModel.snapshot
        XCTAssertNotEqual(cachedSnapshot, .empty)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(viewModel.snapshot, cachedSnapshot)
        let counts = await sampler.callCounts
        XCTAssertGreaterThan(counts.fast, 0)
        XCTAssertGreaterThan(counts.slow, 0)
        XCTAssertGreaterThan(counts.processes, 0)
        let historyCount = await historyStore.appendedCount
        XCTAssertGreaterThan(historyCount, 0)
    }

    func testViewModelMergesDiskCapacityAndActivitySamples() async throws {
        let viewModel = SystemStatusViewModel(
            sampler: StubSystemStatusSampler(),
            historyStore: StubSystemStatusHistoryStore(),
            schedule: .test
        )

        await viewModel.refreshSnapshotNow(referenceDate: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(viewModel.snapshot.disk.usedBytes, 50)
        XCTAssertEqual(viewModel.snapshot.disk.totalBytes, 100)
        XCTAssertEqual(viewModel.snapshot.disk.readBytesPerSecond, 2_048)
        XCTAssertEqual(viewModel.snapshot.disk.writeBytesPerSecond, 1_024)
        XCTAssertEqual(viewModel.snapshot.history.last?.diskReadBytesPerSecond, 2_048)
        XCTAssertEqual(viewModel.snapshot.history.last?.diskWriteBytesPerSecond, 1_024)
    }

    func testViewModelKeepsLiveMetricsFreshWhileThrottlingPublishedChartHistory() async throws {
        let sampler = StubSystemStatusSampler()
        let viewModel = SystemStatusViewModel(
            sampler: sampler,
            historyStore: StubSystemStatusHistoryStore(),
            schedule: .foregroundRestart
        )

        viewModel.startForeground()
        let initialCounts = try await waitForFastSampleCount(atLeast: 2, sampler: sampler)
        let publishedHistoryCount = viewModel.snapshot.history.count
        let cpuUsage = viewModel.snapshot.cpu.usage

        _ = try await waitForFastSampleCount(atLeast: initialCounts.fast + 2, sampler: sampler)
        viewModel.stop()

        XCTAssertEqual(viewModel.snapshot.history.count, publishedHistoryCount)
        XCTAssertNotEqual(viewModel.snapshot.cpu.usage, cpuUsage)
        XCTAssertGreaterThan(publishedHistoryCount, 0)
    }

    func testViewModelRestartsSleepingBackgroundLoopWhenPanelAppears() async throws {
        let sampler = StubSystemStatusSampler()
        let viewModel = SystemStatusViewModel(
            sampler: sampler,
            historyStore: StubSystemStatusHistoryStore(),
            schedule: .foregroundRestart
        )

        viewModel.startBackground()
        let backgroundCounts = try await waitForFastSampleCount(atLeast: 1, sampler: sampler)

        viewModel.startForeground()
        let foregroundCounts = try await waitForFastSampleCount(atLeast: backgroundCounts.fast + 1, sampler: sampler)
        viewModel.stop()

        XCTAssertGreaterThanOrEqual(foregroundCounts.fast, backgroundCounts.fast + 1)
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

    private func waitForFastSampleCount(
        atLeast expectedCount: Int,
        sampler: StubSystemStatusSampler,
        timeout: Duration = .seconds(2)
    ) async throws -> (fast: Int, slow: Int, processes: Int, publicIP: Int) {
        let start = ContinuousClock.now
        while start.duration(to: .now) < timeout {
            let counts = await sampler.callCounts
            if counts.fast >= expectedCount {
                return counts
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        return await sampler.callCounts
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
                usage: min(0.95, 0.20 + Double(fastCallCount) * 0.01),
                loadAverage1Minute: 1.42,
                temperatureCelsius: 42,
                systemPowerWatts: 8.5,
                isCollecting: false
            ),
            memory: SystemStatusMemorySnapshot(
                usedBytes: 4_000,
                totalBytes: 8_000,
                swapUsedBytes: 512,
                swapTotalBytes: 2_048,
                pressure: .normal
            ),
            network: SystemStatusNetworkSnapshot(
                interfaceName: "en0",
                ipAddress: "192.168.1.2",
                publicIPAddress: nil,
                downloadBytesPerSecond: 1_024,
                uploadBytesPerSecond: 512,
                isConnected: true,
                isCollecting: false
            ),
            disk: SystemStatusDiskSnapshot(
                usedBytes: nil,
                totalBytes: nil,
                readBytesPerSecond: 2_048,
                writeBytesPerSecond: 1_024
            )
        )
    }

    func collectSlow() async -> SystemStatusSlowSample {
        slowCallCount += 1
        return SystemStatusSlowSample(
            disk: SystemStatusDiskSnapshot(
                usedBytes: 50,
                totalBytes: 100,
                readBytesPerSecond: nil,
                writeBytesPerSecond: nil
            ),
            battery: SystemStatusBatterySnapshot(
                isAvailable: true,
                level: 0.8,
                state: .acPower,
                timeRemainingMinutes: nil,
                adapterWatts: 70,
                temperatureCelsius: 31,
                healthPercent: 96,
                cycleCount: 120
            ),
            gpu: SystemStatusGPUSnapshot(
                usage: 0.4,
                name: "M1 Pro",
                temperatureCelsius: 43,
                isAvailable: true,
                isCollecting: false
            ),
            hardware: SystemStatusHardwareSnapshot(
                modelName: "MacBookPro18,3",
                chipName: "Apple M1 Pro",
                macOSVersion: "macOS 15.0",
                uptimeSeconds: 3_600,
                totalMemoryBytes: 16_000
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
                memoryPercent: 0.1,
                memoryBytes: 12_582_912
            )
        ]
    }

    func collectPublicIPAddress() async -> String? {
        publicIPCallCount += 1
        return "203.0.113.1"
    }
}

private actor StubSystemStatusHistoryStore: SystemStatusHistoryStoring {
    private(set) var appendedCount = 0
    private var points: [SystemStatusHistoryPoint] = []

    func load(referenceDate: Date) async -> [SystemStatusHistoryPoint] {
        points
    }

    func append(_ point: SystemStatusHistoryPoint, referenceDate: Date) async -> [SystemStatusHistoryPoint] {
        appendedCount += 1
        points.append(point)
        return points
    }
}

private extension SystemStatusSamplingSchedule {
    static let test = SystemStatusSamplingSchedule(
        backgroundFastInterval: .milliseconds(20),
        foregroundFastInterval: .milliseconds(20),
        backgroundSlowInterval: 0,
        foregroundSlowInterval: 0,
        backgroundProcessInterval: 0,
        foregroundProcessInterval: 0,
        backgroundHistoryInterval: 0,
        foregroundHistoryInterval: 0
    )

    static let foregroundRestart = SystemStatusSamplingSchedule(
        backgroundFastInterval: .seconds(30),
        foregroundFastInterval: .milliseconds(20),
        backgroundSlowInterval: 30,
        foregroundSlowInterval: 30,
        backgroundProcessInterval: 30,
        foregroundProcessInterval: 30,
        backgroundHistoryInterval: 30,
        foregroundHistoryInterval: 30
    )
}

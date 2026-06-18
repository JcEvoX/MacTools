import XCTest
@testable import MacTools
@testable import SystemStatusPlugin

final class SystemStatusSamplerTests: XCTestCase {
    func testNetworkChartGeometryDrawsBothSeriesAboveBottomAxis() throws {
        let uploadPoints = SystemStatusHUDDualLineChart.points(
            values: [0, 10],
            width: 100,
            height: 20,
            maximumValue: 10
        )
        let downloadPoints = SystemStatusHUDDualLineChart.points(
            values: [0, 1_000],
            width: 100,
            height: 20,
            maximumValue: 1_000
        )

        let uploadPoint = try XCTUnwrap(uploadPoints.last)
        let downloadPoint = try XCTUnwrap(downloadPoints.last)

        XCTAssertEqual(uploadPoint.x, 100, accuracy: 0.0001)
        XCTAssertEqual(uploadPoint.y, 0, accuracy: 0.0001)
        XCTAssertEqual(downloadPoint.x, 100, accuracy: 0.0001)
        XCTAssertEqual(downloadPoint.y, 0, accuracy: 0.0001)
    }

    func testNetworkChartGeometryUsesReadableSmallChartScale() {
        let ratio = SystemStatusHUDDualLineChart.scaledRatio(value: 10_000, maximumValue: 1_000_000)

        XCTAssertGreaterThan(ratio, 0.09)
        XCTAssertLessThan(ratio, 0.11)
    }

    func testNetworkChartGeometryKeepsPairedSamplesAligned() {
        let samples = SystemStatusHUDDualLineChart.downsamplePeaks(
            [10, 20, 50],
            limit: 120
        )

        XCTAssertEqual(samples, [10, 20, 50])
    }

    func testNetworkChartGeometryClampsNegativeSamplesWithoutPaddingWindow() {
        let samples = SystemStatusHUDDualLineChart.downsamplePeaks(
            [-50, 100],
            limit: 120
        )

        XCTAssertEqual(samples, [0, 100])
    }

    func testNetworkChartGeometryDownsamplesWithBucketPeaks() {
        let samples = SystemStatusHUDDualLineChart.downsamplePeaks(
            [1, 90, 3, 4],
            limit: 2
        )

        XCTAssertEqual(samples, [90, 4])
    }

    func testCPUUsageCalculatorUsesPositiveTickDeltas() throws {
        let previous = SystemStatusCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let current = SystemStatusCPUTicks(user: 150, system: 75, idle: 925, nice: 0)

        let usage = try XCTUnwrap(SystemStatusCPUUsageCalculator.usage(current: current, previous: previous))

        XCTAssertEqual(usage, 0.5, accuracy: 0.0001)
    }

    func testCPUUsageCalculatorReturnsNilForNoElapsedTicks() {
        let ticks = SystemStatusCPUTicks(user: 100, system: 50, idle: 850, nice: 0)

        XCTAssertNil(SystemStatusCPUUsageCalculator.usage(current: ticks, previous: ticks))
    }

    func testPowerNormalizerConvertsTelemetryMilliwatts() throws {
        let watts = try XCTUnwrap(SystemStatusPowerNormalizer.telemetryWatts(fromMilliwatts: 29_813))
        let chargingWatts = try XCTUnwrap(SystemStatusPowerNormalizer.telemetryWatts(fromMilliwatts: -20_629))

        XCTAssertEqual(watts, 29.813, accuracy: 0.0001)
        XCTAssertEqual(chargingWatts, 20.629, accuracy: 0.0001)
    }

    func testPowerNormalizerRejectsUnreasonableTelemetryPower() {
        XCTAssertNil(SystemStatusPowerNormalizer.telemetryWatts(fromMilliwatts: 0))
        XCTAssertNil(SystemStatusPowerNormalizer.telemetryWatts(fromMilliwatts: 1_000_000))
    }

    func testPowerNormalizerConvertsIOReportEnergyUnits() throws {
        XCTAssertEqual(try XCTUnwrap(SystemStatusPowerNormalizer.energyJoules(from: 12_345, unit: "mJ")), 12.345, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SystemStatusPowerNormalizer.energyJoules(from: 12_345_000, unit: "uJ")), 12.345, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(SystemStatusPowerNormalizer.energyJoules(from: 12_345_000_000, unit: "nJ")), 12.345, accuracy: 0.0001)
        XCTAssertNil(SystemStatusPowerNormalizer.energyJoules(from: 12_345, unit: "J"))
    }

    func testPowerCalculatorUsesEnergyDeltaOverElapsedTime() throws {
        let previous = SystemStatusPowerEnergySample(joules: 100, date: Date(timeIntervalSince1970: 1_000))
        let current = SystemStatusPowerEnergySample(joules: 105, date: Date(timeIntervalSince1970: 1_002))

        let watts = try XCTUnwrap(SystemStatusPowerCalculator.watts(current: current, previous: previous))

        XCTAssertEqual(watts, 2.5, accuracy: 0.0001)
    }

    func testPowerCalculatorRejectsInvalidSamples() {
        let previous = SystemStatusPowerEnergySample(joules: 100, date: Date(timeIntervalSince1970: 1_000))
        let sameTime = SystemStatusPowerEnergySample(joules: 105, date: Date(timeIntervalSince1970: 1_000))
        let lowerEnergy = SystemStatusPowerEnergySample(joules: 99, date: Date(timeIntervalSince1970: 1_002))
        let unreasonable = SystemStatusPowerEnergySample(joules: 2_500, date: Date(timeIntervalSince1970: 1_001))

        XCTAssertNil(SystemStatusPowerCalculator.watts(current: sameTime, previous: previous))
        XCTAssertNil(SystemStatusPowerCalculator.watts(current: lowerEnergy, previous: previous))
        XCTAssertNil(SystemStatusPowerCalculator.watts(current: unreasonable, previous: previous))
    }

    func testNetworkRateCalculatorClampsNegativeDeltas() {
        let previous = SystemStatusNetworkCounter(
            key: "en0",
            displayName: "en0",
            receivedBytes: 2_000,
            sentBytes: 2_000,
            ipAddress: "192.168.1.2",
            isUp: true
        )
        let current = SystemStatusNetworkCounter(
            key: "en0",
            displayName: "en0",
            receivedBytes: 1_500,
            sentBytes: 2_400,
            ipAddress: "192.168.1.2",
            isUp: true
        )

        let rate = SystemStatusNetworkRateCalculator.rate(
            current: current,
            previous: previous,
            elapsedSeconds: 2
        )

        XCTAssertEqual(rate?.downloadBytesPerSecond, 0)
        XCTAssertEqual(rate?.uploadBytesPerSecond, 200)
    }

    func testNetworkRateCalculatorDifferentiatesCountersByElapsedTime() {
        let previous = SystemStatusNetworkCounter(
            key: "iflist2:en0",
            displayName: "en0",
            receivedBytes: 10_000,
            sentBytes: 20_000,
            ipAddress: "192.168.1.2",
            isUp: true
        )
        let current = SystemStatusNetworkCounter(
            key: "iflist2:en0",
            displayName: "en0",
            receivedBytes: 16_000,
            sentBytes: 27_500,
            ipAddress: "192.168.1.2",
            isUp: true
        )

        let rate = SystemStatusNetworkRateCalculator.rate(
            current: current,
            previous: previous,
            elapsedSeconds: 3
        )

        XCTAssertEqual(rate?.downloadBytesPerSecond, 2_000)
        XCTAssertEqual(rate?.uploadBytesPerSecond, 2_500)
    }

    func testNetworkRateCalculatorReturnsNilForZeroElapsedTime() {
        let counter = SystemStatusNetworkCounter(
            key: "en0",
            displayName: "en0",
            receivedBytes: 2_000,
            sentBytes: 2_000,
            ipAddress: nil,
            isUp: true
        )

        XCTAssertNil(
            SystemStatusNetworkRateCalculator.rate(
                current: counter,
                previous: counter,
                elapsedSeconds: 0
            )
        )
    }

    func testNetworkRateCalculatorDropsUnreasonableRates() throws {
        let previous = SystemStatusNetworkCounter(
            key: "en0",
            displayName: "en0",
            receivedBytes: 0,
            sentBytes: 0,
            ipAddress: nil,
            isUp: true
        )
        let current = SystemStatusNetworkCounter(
            key: "en0",
            displayName: "en0",
            receivedBytes: 10_000_000_000,
            sentBytes: 9_000_000_000,
            ipAddress: nil,
            isUp: true
        )

        let rate = try XCTUnwrap(
            SystemStatusNetworkRateCalculator.rate(
                current: current,
                previous: previous,
                elapsedSeconds: 1
            )
        )

        XCTAssertEqual(rate.downloadBytesPerSecond, 0)
        XCTAssertEqual(rate.uploadBytesPerSecond, 0)
    }

    func testFriendlyNetworkInterfaceNameUsesHumanReadableKinds() {
        XCTAssertEqual(SystemStatusSampler.friendlyNetworkInterfaceName(for: "utun6"), "VPN")
        XCTAssertEqual(SystemStatusSampler.friendlyNetworkInterfaceName(for: "tap0"), "VPN")
        XCTAssertEqual(
            SystemStatusSampler.friendlyNetworkInterfaceName(
                for: "en0",
                localizedName: "Wi-Fi",
                interfaceType: "IEEE80211"
            ),
            "Wi-Fi"
        )
        XCTAssertEqual(
            SystemStatusSampler.friendlyNetworkInterfaceName(
                for: "en7",
                localizedName: "USB 10/100/1000 LAN",
                interfaceType: "Ethernet",
                wiredDisplayName: "Ethernet"
            ),
            "Ethernet"
        )
        XCTAssertEqual(SystemStatusSampler.friendlyNetworkInterfaceName(for: "eth0"), "有线")
    }

    func testFriendlyNetworkInterfaceNameFallsBackToSystemDisplayNameOrRawName() {
        XCTAssertEqual(
            SystemStatusSampler.friendlyNetworkInterfaceName(for: "foo0", localizedName: "Custom Link"),
            "Custom Link"
        )
        XCTAssertEqual(SystemStatusSampler.friendlyNetworkInterfaceName(for: "foo0"), "foo0")
        XCTAssertEqual(
            SystemStatusSampler.friendlyNetworkInterfaceName(for: "", genericDisplayName: "Network"),
            "Network"
        )
    }

    func testDiskIORateCalculatorDifferentiatesCountersByElapsedTime() {
        let previous = SystemStatusDiskIOCounter(readBytes: 10_000, writeBytes: 20_000)
        let current = SystemStatusDiskIOCounter(readBytes: 16_000, writeBytes: 27_500)

        let rate = SystemStatusDiskIORateCalculator.rate(
            current: current,
            previous: previous,
            elapsedSeconds: 3
        )

        XCTAssertEqual(rate?.readBytesPerSecond, 2_000)
        XCTAssertEqual(rate?.writeBytesPerSecond, 2_500)
    }

    func testDiskIORateCalculatorClampsNegativeDeltas() {
        let previous = SystemStatusDiskIOCounter(readBytes: 2_000, writeBytes: 2_000)
        let current = SystemStatusDiskIOCounter(readBytes: 1_500, writeBytes: 2_400)

        let rate = SystemStatusDiskIORateCalculator.rate(
            current: current,
            previous: previous,
            elapsedSeconds: 2
        )

        XCTAssertEqual(rate?.readBytesPerSecond, 0)
        XCTAssertEqual(rate?.writeBytesPerSecond, 200)
    }

    func testDiskIORateCalculatorReturnsNilForZeroElapsedTime() {
        let counter = SystemStatusDiskIOCounter(readBytes: 2_000, writeBytes: 2_000)

        XCTAssertNil(
            SystemStatusDiskIORateCalculator.rate(
                current: counter,
                previous: counter,
                elapsedSeconds: 0
            )
        )
    }

    func testDiskIORateCalculatorDropsUnreasonableRates() throws {
        let previous = SystemStatusDiskIOCounter(readBytes: 0, writeBytes: 0)
        let current = SystemStatusDiskIOCounter(readBytes: 20_000_000_000, writeBytes: 15_000_000_000)

        let rate = try XCTUnwrap(
            SystemStatusDiskIORateCalculator.rate(
                current: current,
                previous: previous,
                elapsedSeconds: 1
            )
        )

        XCTAssertEqual(rate.readBytesPerSecond, 0)
        XCTAssertEqual(rate.writeBytesPerSecond, 0)
    }

    func testGPUUtilizationNormalizesKnownPerformanceKeys() throws {
        XCTAssertEqual(
            try XCTUnwrap(SystemStatusSampler.gpuUtilization(from: ["Device Utilization %": 42])),
            0.42,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(SystemStatusSampler.gpuUtilization(from: ["GPU Activity(%)": NSNumber(value: 67)])),
            0.67,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(SystemStatusSampler.gpuUtilization(from: ["Renderer Utilization %": 140])),
            1,
            accuracy: 0.0001
        )
        XCTAssertNil(SystemStatusSampler.gpuUtilization(from: [:]))
    }

    func testGPUPerformanceTemperatureUsesIOAcceleratorTemperature() throws {
        XCTAssertEqual(
            try XCTUnwrap(SystemStatusSampler.gpuPerformanceTemperature(from: ["Temperature(C)": 48])),
            48,
            accuracy: 0.0001
        )
        XCTAssertNil(SystemStatusSampler.gpuPerformanceTemperature(from: ["Temperature(C)": 128]))
        XCTAssertNil(SystemStatusSampler.gpuPerformanceTemperature(from: [:]))
    }

    func testGPUNameNormalizesUserVisibleIORegistryModel() throws {
        XCTAssertEqual(
            try XCTUnwrap(SystemStatusSampler.gpuName(from: ["model": "Apple M1 Max"])),
            "M1 Max"
        )
        XCTAssertNil(SystemStatusSampler.gpuName(from: ["IOName": "IOAccelerator"]))
    }

    func testHIDTemperatureParserUsesMatchingSensorPrefixesOnly() {
        let output = """
        +-o AppleHIDTemperatureSensor
        | |   "Product" = "pACC MTR Temp Sensor1"
        | |   "temperature" = 4120
        +-o AppleHIDTemperatureSensor
        | |   "Product" = "GPU MTR Temp Sensor1"
        | |   "temperature" = 47
        +-o AppleSmartBattery
        | |   "Product" = "gas gauge battery"
        | |   "temperature" = 3055
        """

        XCTAssertEqual(
            SystemStatusSampler.hidSensorTemperatures(output: output, keyPrefixes: ["GPU MTR Temp"]),
            [47]
        )
        let cpuTemperatures = SystemStatusSampler.hidSensorTemperatures(output: output, keyPrefixes: ["pACC MTR Temp"])
        XCTAssertEqual(cpuTemperatures.count, 1)
        XCTAssertEqual(cpuTemperatures[0], 41.2, accuracy: 0.0001)
    }

    func testMemoryPressureHeuristicUsesAvailabilityCompressionAndSwap() {
        XCTAssertEqual(
            SystemStatusSampler.memoryPressure(
                freeBytes: 2_000,
                speculativeBytes: 1_000,
                compressedBytes: 500,
                swapUsedBytes: 0,
                totalBytes: 10_000
            ),
            .normal
        )
        XCTAssertEqual(
            SystemStatusSampler.memoryPressure(
                freeBytes: 500,
                speculativeBytes: 100,
                compressedBytes: 1_500,
                swapUsedBytes: 1_200,
                totalBytes: 10_000
            ),
            .warning
        )
        XCTAssertEqual(
            SystemStatusSampler.memoryPressure(
                freeBytes: 100,
                speculativeBytes: 100,
                compressedBytes: 3_000,
                swapUsedBytes: 6_000,
                totalBytes: 10_000
            ),
            .critical
        )
    }

    func testHistoryStorePrunesToRecent24HoursAndMaximumCount() {
        let referenceDate = Date(timeIntervalSince1970: 200_000)
        let oldPoint = SystemStatusHistoryPoint(timestamp: referenceDate.timeIntervalSince1970 - SystemStatusHistoryStore.retention - 1)
        let recentPoint = SystemStatusHistoryPoint(timestamp: referenceDate.timeIntervalSince1970 - 60, cpuUsage: 0.5)

        let pruned = SystemStatusHistoryStore.pruned([recentPoint, oldPoint], referenceDate: referenceDate)

        XCTAssertEqual(pruned, [recentPoint])

        let manyPoints = (0..<(SystemStatusHistoryStore.maximumSampleCount + 10)).map { index in
            SystemStatusHistoryPoint(timestamp: referenceDate.timeIntervalSince1970 - Double(index), cpuUsage: 0.5)
        }
        let capped = SystemStatusHistoryStore.pruned(manyPoints, referenceDate: referenceDate)

        XCTAssertEqual(capped.count, SystemStatusHistoryStore.maximumSampleCount)
        XCTAssertEqual(capped.first?.timestamp, referenceDate.timeIntervalSince1970 - Double(SystemStatusHistoryStore.maximumSampleCount - 1))
        XCTAssertEqual(capped.last?.timestamp, referenceDate.timeIntervalSince1970)
    }

    func testHistoryStorePersistsAndReloadsPrunedSamples() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemStatusHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("history.json")
        let referenceDate = Date(timeIntervalSince1970: 300_000)
        let store = SystemStatusHistoryStore(fileURL: fileURL)
        let oldPoint = SystemStatusHistoryPoint(timestamp: referenceDate.timeIntervalSince1970 - SystemStatusHistoryStore.retention - 5)
        let recentPoint = SystemStatusHistoryPoint(timestamp: referenceDate.timeIntervalSince1970 - 5, cpuUsage: 0.7)

        _ = await store.append(oldPoint, referenceDate: referenceDate)
        let saved = await store.append(recentPoint, referenceDate: referenceDate)

        XCTAssertEqual(saved, [recentPoint])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let reloaded = await SystemStatusHistoryStore(fileURL: fileURL).load(referenceDate: referenceDate)
        XCTAssertEqual(reloaded, [recentPoint])
    }

    func testProcessParserSortsByCPUThenMemoryThenPIDAndLimits() {
        let output = """
          42   8.5  1.0  10240 /Applications/Alpha.app/Contents/MacOS/Alpha
           7  12.0  2.0  20480 /usr/bin/beta
           9  12.0  5.0  40960 /usr/bin/gamma
           6  12.0  5.0  51200 /usr/bin/delta
          11   1.0  9.0   1024 /usr/bin/epsilon
        """

        let processes = SystemStatusProcessParser.parsePSOutput(output, limit: 3)

        XCTAssertEqual(processes.map(\.pid), [6, 9, 7])
        XCTAssertEqual(processes.map(\.displayName), ["delta", "gamma", "beta"])
        XCTAssertEqual(processes[0].cpuPercent, 12)
        XCTAssertEqual(processes[0].memoryPercent, 5)
        XCTAssertEqual(processes[0].memoryBytes, 52_428_800)
    }

    func testProcessParserKeepsAppBundleNamesWithSpaces() throws {
        let output = """
          99   4.0  2.5  10240 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --type=renderer
         100   3.0  1.0   2048 Cursor Helper (Plugin): extension-host
        """

        let processes = SystemStatusProcessParser.parsePSOutput(output, limit: 2)

        XCTAssertEqual(processes.count, 2)
        XCTAssertEqual(processes[0].displayName, "Google Chrome")
        XCTAssertEqual(processes[0].command, "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --type=renderer")
        XCTAssertEqual(processes[1].displayName, "Cursor Helper (Plugin): extension-host")
    }

    func testFormatterOutputsExpectedValues() {
        XCTAssertEqual(SystemStatusFormatter.percent(0.425), "43%")
        XCTAssertEqual(SystemStatusFormatter.wholePercent(12.34, fractionDigits: 1), "12.3%")
        XCTAssertEqual(SystemStatusFormatter.bytes(1_073_741_824), "1.0 GB")
        XCTAssertEqual(SystemStatusFormatter.speed(1_048_576), "1.0 MB/s")
        XCTAssertEqual(SystemStatusFormatter.temperature(30.6), "31°C")
        XCTAssertEqual(SystemStatusFormatter.temperature(nil), "—°C")
        XCTAssertEqual(SystemStatusFormatter.power(7.26), "7.3W")
        XCTAssertEqual(SystemStatusFormatter.power(29.813), "30W")
        XCTAssertEqual(SystemStatusFormatter.power(nil), "—W")
        XCTAssertEqual(SystemStatusFormatter.rpm(1_234.4), "1234 RPM")
        XCTAssertEqual(SystemStatusFormatter.timeRemaining(minutes: 65), "1h 5m")
        XCTAssertEqual(SystemStatusFormatter.timeRemaining(minutes: nil), "估算中")
        XCTAssertEqual(SystemStatusFormatter.uptime(90_000), "1d 1h")
    }
}

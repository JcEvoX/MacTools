import XCTest
@testable import MacTools
@testable import SystemStatusPlugin

final class SystemStatusSamplerTests: XCTestCase {
    func testNetworkChartDownsamplesWithBucketPeaks() {
        XCTAssertEqual(
            SystemStatusHUDDualLineChart.downsamplePeaks([1, 90, 3, 4], limit: 2),
            [90, 4]
        )
    }

    func testCPUUsageCalculatorUsesPositiveTickDeltas() throws {
        let usage = try XCTUnwrap(SystemStatusCPUUsageCalculator.usage(
            current: SystemStatusCPUTicks(user: 150, system: 75, idle: 925, nice: 0),
            previous: SystemStatusCPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        ))

        XCTAssertEqual(usage, 0.5, accuracy: 0.0001)
    }

    func testPowerCalculatorUsesEnergyDeltaOverElapsedTime() throws {
        let watts = try XCTUnwrap(SystemStatusPowerCalculator.watts(
            current: SystemStatusPowerEnergySample(joules: 105, date: Date(timeIntervalSince1970: 1_002)),
            previous: SystemStatusPowerEnergySample(joules: 100, date: Date(timeIntervalSince1970: 1_000))
        ))

        XCTAssertEqual(watts, 2.5, accuracy: 0.0001)
    }

    func testNetworkRateCalculatorDifferentiatesCountersByElapsedTime() {
        let rate = SystemStatusNetworkRateCalculator.rate(
            current: SystemStatusNetworkCounter(
                key: "iflist2:en0",
                displayName: "en0",
                receivedBytes: 16_000,
                sentBytes: 27_500,
                ipAddress: "192.168.1.2",
                isUp: true
            ),
            previous: SystemStatusNetworkCounter(
                key: "iflist2:en0",
                displayName: "en0",
                receivedBytes: 10_000,
                sentBytes: 20_000,
                ipAddress: "192.168.1.2",
                isUp: true
            ),
            elapsedSeconds: 3
        )

        XCTAssertEqual(rate?.downloadBytesPerSecond, 2_000)
        XCTAssertEqual(rate?.uploadBytesPerSecond, 2_500)
    }

    func testDiskIORateCalculatorDifferentiatesCountersByElapsedTime() {
        let rate = SystemStatusDiskIORateCalculator.rate(
            current: SystemStatusDiskIOCounter(readBytes: 16_000, writeBytes: 27_500),
            previous: SystemStatusDiskIOCounter(readBytes: 10_000, writeBytes: 20_000),
            elapsedSeconds: 3
        )

        XCTAssertEqual(rate?.readBytesPerSecond, 2_000)
        XCTAssertEqual(rate?.writeBytesPerSecond, 2_500)
    }

    func testProcessParserSortsByCPUThenMemoryThenPIDAndLimits() {
        let output = """
          42   8.5  1.0  10240 /Applications/Alpha.app/Contents/MacOS/Alpha
           7  12.0  2.0  20480 /usr/bin/beta
           9  12.0  5.0  40960 /usr/bin/gamma
           6  12.0  5.0  51200 /usr/bin/delta
        """

        let processes = SystemStatusProcessParser.parsePSOutput(output, limit: 3)

        XCTAssertEqual(processes.map(\.pid), [6, 9, 7])
        XCTAssertEqual(processes.map(\.displayName), ["delta", "gamma", "beta"])
    }

    func testFormatterOutputsExpectedValues() {
        XCTAssertEqual(SystemStatusFormatter.percent(0.425), "43%")
        XCTAssertEqual(SystemStatusFormatter.bytes(1_073_741_824), "1.0 GB")
        XCTAssertEqual(SystemStatusFormatter.speed(1_048_576), "1.0 MB/s")
        XCTAssertEqual(SystemStatusFormatter.temperature(nil), "—°C")
        XCTAssertEqual(SystemStatusFormatter.power(29.813), "30W")
        XCTAssertEqual(SystemStatusFormatter.uptime(90_000), "1d 1h")
    }
}

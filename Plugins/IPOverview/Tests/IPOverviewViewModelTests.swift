import Foundation
import MacToolsPluginKit
import XCTest
@testable import IPOverviewPlugin

@MainActor
final class IPOverviewViewModelTests: XCTestCase {
    func testDiagnosticsIfNeededRunsConnectivityAndLeakTestsOnce() async {
        let connectivityChecker = RecordingConnectivityChecker()
        let leakTester = RecordingLeakTester()
        let viewModel = IPOverviewViewModel(
            provider: RecordingProvider(),
            connectivityChecker: connectivityChecker,
            leakTester: leakTester,
            storage: IPOverviewMemoryStorage()
        )

        viewModel.checkDiagnosticsIfNeeded()

        await waitUntil { !viewModel.isRefreshingAll }

        var connectivityCount = await connectivityChecker.checkedCountValue()
        var webRTCCount = await leakTester.webRTCCountValue()
        var dnsCount = await leakTester.dnsCountValue()
        XCTAssertEqual(connectivityCount, IPOverviewConnectivityTarget.defaults.count)
        XCTAssertEqual(webRTCCount, IPOverviewWebRTCTarget.defaults.count)
        XCTAssertEqual(dnsCount, 4)

        viewModel.checkDiagnosticsIfNeeded()
        try? await Task.sleep(for: .milliseconds(40))

        connectivityCount = await connectivityChecker.checkedCountValue()
        webRTCCount = await leakTester.webRTCCountValue()
        dnsCount = await leakTester.dnsCountValue()
        XCTAssertEqual(connectivityCount, IPOverviewConnectivityTarget.defaults.count)
        XCTAssertEqual(webRTCCount, IPOverviewWebRTCTarget.defaults.count)
        XCTAssertEqual(dnsCount, 4)
    }

    func testRefreshAllRunsIPConnectivityAndLeakTestsEveryTime() async {
        let provider = RecordingProvider()
        let connectivityChecker = RecordingConnectivityChecker()
        let leakTester = RecordingLeakTester()
        let viewModel = IPOverviewViewModel(
            provider: provider,
            connectivityChecker: connectivityChecker,
            leakTester: leakTester,
            storage: IPOverviewMemoryStorage()
        )

        viewModel.refreshAll()
        await waitUntil { !viewModel.isRefreshingAll && viewModel.snapshot.lastUpdated != nil }

        var providerCount = await provider.callCountValue()
        var connectivityCount = await connectivityChecker.checkedCountValue()
        var webRTCCount = await leakTester.webRTCCountValue()
        var dnsCount = await leakTester.dnsCountValue()
        XCTAssertEqual(providerCount, 1)
        XCTAssertEqual(connectivityCount, IPOverviewConnectivityTarget.defaults.count)
        XCTAssertEqual(webRTCCount, IPOverviewWebRTCTarget.defaults.count)
        XCTAssertEqual(dnsCount, 4)

        viewModel.refreshAll()
        await waitUntil {
            let count = await provider.callCountValue()
            return !viewModel.isRefreshingAll && count == 2
        }

        providerCount = await provider.callCountValue()
        connectivityCount = await connectivityChecker.checkedCountValue()
        webRTCCount = await leakTester.webRTCCountValue()
        dnsCount = await leakTester.dnsCountValue()
        XCTAssertEqual(providerCount, 2)
        XCTAssertEqual(connectivityCount, IPOverviewConnectivityTarget.defaults.count * 2)
        XCTAssertEqual(webRTCCount, IPOverviewWebRTCTarget.defaults.count * 2)
        XCTAssertEqual(dnsCount, 8)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        predicate: @escaping @MainActor () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private actor RecordingProvider: IPOverviewProviding {
    private(set) var callCount = 0

    func callCountValue() -> Int {
        callCount
    }

    func collectSnapshot() async -> IPOverviewSnapshot {
        callCount += 1
        return IPOverviewSnapshot(
            publicIPv4: IPOverviewPublicIPResult(
                family: .ipv4,
                ip: "203.0.113.10",
                source: "Test"
            ),
            publicIPv6: nil,
            localAddresses: [],
            geoInfoByIP: [:],
            sourceResults: [],
            lastUpdated: Date(),
            errorMessage: nil,
            isRefreshing: false
        )
    }
}

private actor RecordingConnectivityChecker: IPOverviewConnectivityChecking {
    private(set) var checkedCount = 0

    func checkedCountValue() -> Int {
        checkedCount
    }

    func check(target: IPOverviewConnectivityTarget) async -> IPOverviewConnectivityResult {
        checkedCount += 1
        return IPOverviewConnectivityResult(
            id: target.id,
            target: target,
            status: .reachable(milliseconds: 12)
        )
    }
}

private actor RecordingLeakTester: IPOverviewLeakTesting {
    private(set) var webRTCCount = 0
    private(set) var dnsCount = 0

    func webRTCCountValue() -> Int {
        webRTCCount
    }

    func dnsCountValue() -> Int {
        dnsCount
    }

    func checkWebRTC(target: IPOverviewWebRTCTarget) async -> IPOverviewLeakTestResult {
        webRTCCount += 1
        return IPOverviewLeakTestResult(
            id: target.id,
            name: target.name,
            status: .success(IPOverviewLeakEndpoint(
                ip: "203.0.113.20",
                natType: "测试 NAT",
                country: "United States",
                countryCode: "US",
                organization: "Example Network"
            ))
        )
    }

    func checkDNS(id: String, name: String) async -> IPOverviewLeakTestResult {
        dnsCount += 1
        return IPOverviewLeakTestResult(
            id: id,
            name: name,
            status: .success(IPOverviewLeakEndpoint(
                ip: "203.0.113.53",
                natType: nil,
                country: "United States",
                countryCode: "US",
                organization: "Example DNS"
            ))
        )
    }
}

@MainActor
private final class IPOverviewMemoryStorage: PluginStorage {
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func data(forKey key: String) -> Data? {
        values[key] as? Data
    }

    func string(forKey key: String) -> String? {
        values[key] as? String
    }

    func stringArray(forKey key: String) -> [String]? {
        values[key] as? [String]
    }

    func integer(forKey key: String) -> Int {
        values[key] as? Int ?? 0
    }

    func bool(forKey key: String) -> Bool {
        values[key] as? Bool ?? false
    }

    func set(_ value: Any?, forKey key: String) {
        values[key] = value
    }

    func removeObject(forKey key: String) {
        values.removeValue(forKey: key)
    }

    func migrateValueIfNeeded(fromLegacyKey legacyKey: String, to key: String) {}
}

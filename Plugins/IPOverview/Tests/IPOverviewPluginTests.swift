import XCTest
import MacToolsPluginKit
@testable import IPOverviewPlugin

@MainActor
final class IPOverviewPluginTests: XCTestCase {
    func testMetadataUsesStableIdentifier() {
        let plugin = IPOverviewPlugin()

        XCTAssertEqual(plugin.metadata.id, "ip-overview")
        XCTAssertEqual(plugin.metadata.title, "IP 概览")
    }

    func testPluginIsComponentOnly() {
        let plugin = IPOverviewPlugin()

        XCTAssertNil(plugin.primaryPanel)
        XCTAssertNotNil(plugin.componentPanel)
    }

    func testComponentUsesCompactLandingSpan() {
        let plugin = IPOverviewPlugin()

        XCTAssertEqual(plugin.descriptor.span, .fourByTwo)
    }

    func testComponentExpandsForDetails() {
        let viewModel = IPOverviewViewModel(storage: IPOverviewPluginTestStorage())
        let plugin = IPOverviewPlugin(viewModel: viewModel)

        XCTAssertEqual(plugin.descriptor.span, .fourByTwo)

        viewModel.showDetails()

        XCTAssertEqual(plugin.descriptor.span, PluginComponentSpan(width: 4, height: 8)!)
    }
}

@MainActor
private final class IPOverviewPluginTestStorage: PluginStorage {
    private var values: [String: Any] = [:]

    func object(forKey key: String) -> Any? { values[key] }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    func migrateValueIfNeeded(fromLegacyKey legacyKey: String, to key: String) {}
}

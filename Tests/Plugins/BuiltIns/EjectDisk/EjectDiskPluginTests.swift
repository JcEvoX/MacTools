import XCTest
@testable import MacTools

@MainActor
final class EjectDiskPluginTests: XCTestCase {
    func testMetadataIdentifiesEjectDiskPlugin() {
        let plugin = EjectDiskPlugin()

        XCTAssertEqual(plugin.metadata.id, "eject-disk")
        XCTAssertEqual(plugin.metadata.title, "推出磁盘")
    }

    func testControlStyleIsButton() {
        let plugin = EjectDiskPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .button)
        XCTAssertEqual(plugin.primaryPanelDescriptor.buttonTitle, "推出")
    }

    func testInitialStateHasEjectedOffAndIsDisabled() {
        let plugin = EjectDiskPlugin()

        let state = plugin.primaryPanelState
        XCTAssertFalse(state.isOn)
        XCTAssertFalse(state.isEnabled)
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = EjectDiskPlugin()

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testDefaultPluginHostIncludesEjectDisk() {
        let host = PluginHost()

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "eject-disk" })
    }

    func testPluginDescriptionMatches() {
        let plugin = EjectDiskPlugin()

        XCTAssertEqual(plugin.metadata.defaultDescription, "推出所有可移动磁盘")
    }

    func testSubtitleMatchesDefaultDescriptionByDefault() {
        let plugin = EjectDiskPlugin()

        XCTAssertEqual(plugin.primaryPanelState.subtitle, plugin.metadata.defaultDescription)
    }
}

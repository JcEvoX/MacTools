import XCTest
@testable import MacTools

@MainActor
final class EjectDiskPluginTests: XCTestCase {
    func testManifestIdentifiesEjectDiskPlugin() {
        let plugin = EjectDiskPlugin()

        XCTAssertEqual(plugin.manifest.id, "eject-disk")
        XCTAssertEqual(plugin.manifest.title, "推出磁盘")
    }

    func testControlStyleIsButton() {
        let plugin = EjectDiskPlugin()

        XCTAssertEqual(plugin.manifest.controlStyle, .button)
        XCTAssertEqual(plugin.manifest.buttonTitle, "推出")
    }

    func testInitialStateHasEjectedOffAndIsDisabled() {
        let plugin = EjectDiskPlugin()

        let state = plugin.panelState
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

        XCTAssertEqual(plugin.manifest.defaultDescription, "推出所有可移动磁盘")
    }

    func testSubtitleMatchesDefaultDescriptionByDefault() {
        let plugin = EjectDiskPlugin()

        XCTAssertEqual(plugin.panelState.subtitle, plugin.manifest.defaultDescription)
    }
}


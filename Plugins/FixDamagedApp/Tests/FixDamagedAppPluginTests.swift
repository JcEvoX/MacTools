import XCTest
@testable import MacTools
@testable import FixDamagedAppPlugin

@MainActor
final class FixDamagedAppPluginTests: XCTestCase {

    // MARK: - Metadata

    func testMetadataID() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertEqual(plugin.metadata.id, "fix-damaged-app")
    }

    func testMetadataTitle() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertEqual(plugin.metadata.title, "修复损坏应用")
    }

    func testMetadataDefaultDescription() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertEqual(plugin.metadata.defaultDescription, "移除隔离属性，解决「已损坏」或「不受信任」提示")
    }

    // MARK: - Primary Panel Descriptor

    func testControlStyleIsButton() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .button)
        XCTAssertEqual(plugin.primaryPanelDescriptor.buttonTitle, "选择")
    }

    func testMenuActionBehaviorIsDismissBeforeHandling() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.menuActionBehavior, .dismissBeforeHandling)
    }

    // MARK: - Initial Primary Panel State

    func testInitialPrimaryStateIsEnabledAndNotOn() {
        let plugin = FixDamagedAppPlugin()

        let state = plugin.primaryPanelState
        XCTAssertTrue(state.isEnabled)
        XCTAssertFalse(state.isOn)
    }

    func testInitialPrimarySubtitlePromptsSelection() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertEqual(plugin.primaryPanelState.subtitle, "选择 .app 文件以修复")
    }

    func testInitialPrimaryStateHasNoError() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertNil(plugin.primaryPanelState.errorMessage)
    }

    // MARK: - Permission & Settings

    func testPermissionRequirementsIsEmpty() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testSettingsSectionsIsEmpty() {
        let plugin = FixDamagedAppPlugin()

        XCTAssertTrue(plugin.settingsSections.isEmpty)
    }

    func testPermissionStateAlwaysGranted() {
        let plugin = FixDamagedAppPlugin()

        let state = plugin.permissionState(for: "any-permission-id")
        XCTAssertTrue(state.isGranted)
    }

    // MARK: - Plugin Host Integration

    func testPluginHostIncludesFixDamagedApp() {
        let host = makePluginHostForTests(plugins: [FixDamagedAppPlugin()])

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "fix-damaged-app" })
    }
}

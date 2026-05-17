import XCTest
@testable import MacTools
@testable import LockScreenPlugin

@MainActor
final class LockScreenPluginTests: XCTestCase {
    func testMetadataIdentifiesLockScreenPlugin() {
        let plugin = LockScreenPlugin()

        XCTAssertEqual(plugin.metadata.id, "lock-screen")
        XCTAssertEqual(plugin.metadata.title, "锁定屏幕")
    }

    func testControlStyleIsButton() {
        let plugin = LockScreenPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .button)
        XCTAssertEqual(plugin.primaryPanelDescriptor.buttonTitle, "锁定")
    }

    func testInitialStateIsOffAndEnabled() {
        let plugin = LockScreenPlugin()

        let state = plugin.primaryPanelState
        XCTAssertFalse(state.isOn)
        XCTAssertTrue(state.isEnabled)
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = LockScreenPlugin()

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testMenuActionBehaviorDismissesBeforeHandling() {
        let plugin = LockScreenPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.menuActionBehavior, .dismissBeforeHandling)
    }

    func testPluginHostIncludesLockScreenWhenProvided() {
        let host = makePluginHostForTests(plugins: [LockScreenPlugin()])

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "lock-screen" })
    }

    func testPluginDescriptionMatches() {
        let plugin = LockScreenPlugin()

        XCTAssertEqual(plugin.metadata.defaultDescription, "立即锁定屏幕")
    }

    func testHandleUnknownActionDoesNothing() {
        let plugin = LockScreenPlugin()

        plugin.handleAction(.setSwitch(true))
    }
}

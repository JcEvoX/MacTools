import XCTest
@testable import MacTools
@testable import DisplaySleepPlugin

@MainActor
final class DisplaySleepPluginTests: XCTestCase {
    func testMetadataIdentifiesDisplaySleepPlugin() {
        let plugin = DisplaySleepPlugin()

        XCTAssertEqual(plugin.metadata.id, "display-sleep")
        XCTAssertEqual(plugin.metadata.title, "显示器休眠")
    }

    func testControlStyleIsButton() {
        let plugin = DisplaySleepPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .button)
        XCTAssertEqual(plugin.primaryPanelDescriptor.buttonTitle, "休眠")
    }

    func testInitialStateIsOffAndEnabled() {
        let plugin = DisplaySleepPlugin()

        let state = plugin.primaryPanelState
        XCTAssertFalse(state.isOn)
        XCTAssertTrue(state.isEnabled)
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = DisplaySleepPlugin()

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testMenuActionBehaviorDismissesBeforeHandling() {
        let plugin = DisplaySleepPlugin()

        XCTAssertEqual(plugin.primaryPanelDescriptor.menuActionBehavior, .dismissBeforeHandling)
    }

    func testPluginHostIncludesDisplaySleepWhenProvided() {
        let host = makePluginHostForTests(plugins: [DisplaySleepPlugin()])

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "display-sleep" })
    }

    func testPluginDescriptionMatches() {
        let plugin = DisplaySleepPlugin()

        XCTAssertEqual(plugin.metadata.defaultDescription, "立即让显示器休眠")
    }

    func testHandleUnknownActionDoesNothing() {
        let plugin = DisplaySleepPlugin()

        plugin.handleAction(.setSwitch(true))
    }
}

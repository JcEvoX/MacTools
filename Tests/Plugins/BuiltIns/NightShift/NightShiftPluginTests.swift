import XCTest
@testable import MacTools

@MainActor
final class NightShiftPluginTests: XCTestCase {
    private struct MockController: NightShiftControlling {
        var status: Bool
        var setEnabledResult: Bool = true

        func getStatus() -> Bool { status }
        func setEnabled(_ enabled: Bool) -> Bool { setEnabledResult }
    }

    func testMetadataIdentifiesNightShiftPlugin() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertEqual(plugin.metadata.id, "night-shift")
        XCTAssertEqual(plugin.metadata.title, "夜览")
    }

    func testControlStyleIsSwitch() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .switch)
    }

    func testPanelStateReflectsDisabledStatus() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "已关闭")
    }

    func testPanelStateReflectsEnabledStatus() {
        let plugin = NightShiftPlugin(controller: MockController(status: true))

        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "已开启")
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testDefaultPluginHostIncludesNightShift() {
        let host = PluginHost()

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "night-shift" })
    }

    func testHandleActionEnablesNightShift() {
        var controller = MockController(status: false)
        controller.setEnabledResult = true
        let plugin = NightShiftPlugin(controller: controller)

        plugin.handleAction(.setSwitch(true))

        XCTAssertTrue(plugin.primaryPanelState.isOn)
    }

    func testHandleActionOnFailureSetsErrorMessage() {
        var controller = MockController(status: true)
        controller.setEnabledResult = false
        let plugin = NightShiftPlugin(controller: controller)

        plugin.handleAction(.setSwitch(false))

        XCTAssertNotNil(plugin.primaryPanelState.errorMessage)
    }
}

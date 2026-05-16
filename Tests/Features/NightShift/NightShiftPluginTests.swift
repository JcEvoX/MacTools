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

    func testManifestIdentifiesNightShiftPlugin() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertEqual(plugin.manifest.id, "night-shift")
        XCTAssertEqual(plugin.manifest.title, "夜览")
    }

    func testControlStyleIsSwitch() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertEqual(plugin.manifest.controlStyle, .switch)
    }

    func testPanelStateReflectsDisabledStatus() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertFalse(plugin.panelState.isOn)
        XCTAssertEqual(plugin.panelState.subtitle, "已关闭")
    }

    func testPanelStateReflectsEnabledStatus() {
        let plugin = NightShiftPlugin(controller: MockController(status: true))

        XCTAssertTrue(plugin.panelState.isOn)
        XCTAssertEqual(plugin.panelState.subtitle, "已开启")
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = NightShiftPlugin(controller: MockController(status: false))

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testDefaultPluginHostIncludesNightShift() {
        let host = PluginHost()

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "night-shift" })
    }

    func testHandlePanelActionEnablesNightShift() {
        var controller = MockController(status: false)
        controller.setEnabledResult = true
        let plugin = NightShiftPlugin(controller: controller)

        plugin.handlePanelAction(.setSwitch(true))

        XCTAssertTrue(plugin.panelState.isOn)
    }

    func testHandlePanelActionOnFailureSetsErrorMessage() {
        var controller = MockController(status: true)
        controller.setEnabledResult = false
        let plugin = NightShiftPlugin(controller: controller)

        plugin.handlePanelAction(.setSwitch(false))

        XCTAssertNotNil(plugin.panelState.errorMessage)
    }
}

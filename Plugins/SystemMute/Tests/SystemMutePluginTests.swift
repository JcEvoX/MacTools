import XCTest
@testable import MacTools
@testable import SystemMutePlugin

@MainActor
final class SystemMutePluginTests: XCTestCase {
    private struct MockController: SystemAudioControlling {
        var muteState: Bool
        var setMuteResult: Bool = true

        func readMuteState() -> Bool { muteState }
        func setMuteState(_ muted: Bool) -> Bool { setMuteResult }
    }

    func testMetadataIdentifiesSystemMutePlugin() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))

        XCTAssertEqual(plugin.metadata.id, "system-mute")
        XCTAssertEqual(plugin.metadata.title, "系统静音")
    }

    func testControlStyleIsSwitch() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))

        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .switch)
    }

    func testPanelStateReflectsUnmutedStatus() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "未静音")
    }

    func testPanelStateReflectsMutedStatus() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: true))

        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "已静音")
    }

    func testPanelStateIsAlwaysEnabled() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))

        XCTAssertTrue(plugin.primaryPanelState.isEnabled)
    }

    func testPermissionRequirementsIsEmpty() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))

        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }

    func testPluginHostIncludesSystemMuteWhenProvided() {
        let host = makePluginHostForTests(plugins: [SystemMutePlugin(controller: MockController(muteState: false))])

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "system-mute" })
    }

    func testHandleActionMutesWhenSwitchedOn() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))

        plugin.handleAction(.setSwitch(true))

        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertNil(plugin.primaryPanelState.errorMessage)
    }

    func testHandleActionUnmutesWhenSwitchedOff() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: true))

        plugin.handleAction(.setSwitch(false))

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertNil(plugin.primaryPanelState.errorMessage)
    }

    func testHandleActionOnFailureSetsErrorMessage() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false, setMuteResult: false))

        plugin.handleAction(.setSwitch(true))

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertNotNil(plugin.primaryPanelState.errorMessage)
    }

    func testRefreshDoesNotCallOnStateChangeWhenStateUnchanged() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))
        var callCount = 0
        plugin.onStateChange = { callCount += 1 }

        plugin.refresh()

        XCTAssertEqual(callCount, 0)
    }

    func testHandleActionCallsOnStateChange() {
        let plugin = SystemMutePlugin(controller: MockController(muteState: false))
        var callCount = 0
        plugin.onStateChange = { callCount += 1 }

        plugin.handleAction(.setSwitch(true))

        XCTAssertEqual(callCount, 1)
    }
}

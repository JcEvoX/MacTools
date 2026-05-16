import XCTest
@testable import MacTools

@MainActor
final class DisplayTrueColorPluginTests: XCTestCase {
    func testPluginManifest() {
        let plugin = DisplayTrueColorPlugin(client: MockTrueToneClient())

        XCTAssertEqual(plugin.manifest.id, "display-true-color")
        XCTAssertEqual(plugin.manifest.title, "原彩显示")
        XCTAssertEqual(plugin.manifest.controlStyle, .switch)
        XCTAssertEqual(plugin.manifest.order, 25)
    }

    func testPluginIsIncludedInDefaultPluginHost() {
        let host = PluginHost()

        XCTAssertTrue(host.panelItems.contains { $0.id == "display-true-color" })
    }

    func testPanelStateWhenSupportedAndEnabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: true)
        let plugin = DisplayTrueColorPlugin(client: client)

        let state = plugin.panelState
        XCTAssertTrue(state.isOn)
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.subtitle, "已开启")
    }

    func testPanelStateWhenSupportedAndDisabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: false)
        let plugin = DisplayTrueColorPlugin(client: client)

        let state = plugin.panelState
        XCTAssertFalse(state.isOn)
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.subtitle, "已关闭")
    }

    func testPanelStateWhenNotSupported() {
        let client = MockTrueToneClient(isSupported: false, isEnabled: nil)
        let plugin = DisplayTrueColorPlugin(client: client)

        let state = plugin.panelState
        XCTAssertFalse(state.isOn)
        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.subtitle, "不支持")
    }

    func testToggleOnCallsSetEnabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: false)
        let plugin = DisplayTrueColorPlugin(client: client)

        plugin.handlePanelAction(.setSwitch(true))

        XCTAssertTrue(client.lastSetEnabled == true)
        XCTAssertTrue(plugin.panelState.isOn)
    }

    func testToggleOffCallsSetEnabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: true)
        let plugin = DisplayTrueColorPlugin(client: client)

        plugin.handlePanelAction(.setSwitch(false))

        XCTAssertTrue(client.lastSetEnabled == false)
        XCTAssertFalse(plugin.panelState.isOn)
    }

    func testToggleDoesNothingWhenNotSupported() {
        let client = MockTrueToneClient(isSupported: false, isEnabled: nil)
        let plugin = DisplayTrueColorPlugin(client: client)

        plugin.handlePanelAction(.setSwitch(true))

        XCTAssertNil(client.lastSetEnabled)
    }

    func testRefreshUpdatesState() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: false)
        let plugin = DisplayTrueColorPlugin(client: client)

        XCTAssertFalse(plugin.panelState.isOn)

        client.stubbedEnabled = true
        plugin.refresh()

        XCTAssertTrue(plugin.panelState.isOn)
    }

    func testPermissionRequirementsAreEmpty() {
        let plugin = DisplayTrueColorPlugin(client: MockTrueToneClient())
        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }
}

// MARK: - Mock

@MainActor
final class MockTrueToneClient: TrueToneClient {
    private let supported: Bool
    var stubbedEnabled: Bool?
    private(set) var lastSetEnabled: Bool?

    init(isSupported: Bool = true, isEnabled: Bool? = false) {
        self.supported = isSupported
        self.stubbedEnabled = isEnabled
    }

    var isSupported: Bool { supported }
    var isEnabled: Bool? { stubbedEnabled }

    func setEnabled(_ enabled: Bool) {
        stubbedEnabled = enabled
        lastSetEnabled = enabled
    }
}

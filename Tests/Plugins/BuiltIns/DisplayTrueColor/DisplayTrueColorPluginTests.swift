import XCTest
@testable import MacTools

@MainActor
final class DisplayTrueColorPluginTests: XCTestCase {
    private let suiteName = "DisplayTrueColorPluginTests"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testPluginMetadataAndPrimaryPanelDescriptor() {
        let plugin = DisplayTrueColorPlugin(client: MockTrueToneClient())

        XCTAssertEqual(plugin.metadata.id, "display-true-color")
        XCTAssertEqual(plugin.metadata.title, "原彩显示")
        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .switch)
        XCTAssertEqual(plugin.metadata.order, 25)
    }

    func testPluginIsIncludedInDefaultPluginHost() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let host = PluginHost(
            plugins: BuiltInPluginRegistry().makePlugins(),
            shortcutStore: ShortcutStore(userDefaults: defaults),
            pluginDisplayPreferencesStore: PluginDisplayPreferencesStore(userDefaults: defaults),
            globalShortcutManager: GlobalShortcutManager()
        )

        XCTAssertTrue(host.panelItems.contains { $0.id == "display-true-color" })
    }

    func testPanelStateWhenSupportedAndEnabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: true)
        let plugin = DisplayTrueColorPlugin(client: client)

        let state = plugin.primaryPanelState
        XCTAssertTrue(state.isOn)
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.subtitle, "已开启")
    }

    func testPanelStateWhenSupportedAndDisabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: false)
        let plugin = DisplayTrueColorPlugin(client: client)

        let state = plugin.primaryPanelState
        XCTAssertFalse(state.isOn)
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.subtitle, "已关闭")
    }

    func testPanelStateWhenNotSupported() {
        let client = MockTrueToneClient(isSupported: false, isEnabled: nil)
        let plugin = DisplayTrueColorPlugin(client: client)

        let state = plugin.primaryPanelState
        XCTAssertFalse(state.isOn)
        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.subtitle, "不支持")
    }

    func testToggleOnCallsSetEnabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: false)
        let plugin = DisplayTrueColorPlugin(client: client)

        plugin.handleAction(.setSwitch(true))

        XCTAssertTrue(client.lastSetEnabled == true)
        XCTAssertTrue(plugin.primaryPanelState.isOn)
    }

    func testToggleOffCallsSetEnabled() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: true)
        let plugin = DisplayTrueColorPlugin(client: client)

        plugin.handleAction(.setSwitch(false))

        XCTAssertTrue(client.lastSetEnabled == false)
        XCTAssertFalse(plugin.primaryPanelState.isOn)
    }

    func testToggleDoesNothingWhenNotSupported() {
        let client = MockTrueToneClient(isSupported: false, isEnabled: nil)
        let plugin = DisplayTrueColorPlugin(client: client)

        plugin.handleAction(.setSwitch(true))

        XCTAssertNil(client.lastSetEnabled)
    }

    func testRefreshUpdatesState() {
        let client = MockTrueToneClient(isSupported: true, isEnabled: false)
        let plugin = DisplayTrueColorPlugin(client: client)

        XCTAssertFalse(plugin.primaryPanelState.isOn)

        client.stubbedEnabled = true
        plugin.refresh()

        XCTAssertTrue(plugin.primaryPanelState.isOn)
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

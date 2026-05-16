import XCTest
@testable import MacTools

@MainActor
final class HideDockPluginTests: XCTestCase {
    func testMetadataIdentifiesHideDockPlugin() {
        let plugin = HideDockPlugin(
            commandRunner: MockDockCommandRunner(),
            stateReader: { false }
        )

        XCTAssertEqual(plugin.metadata.id, "hide-dock")
        XCTAssertEqual(plugin.metadata.title, "隐藏 Dock")
        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .switch)
    }

    func testInitialStateReflectsStateReader() {
        let plugin = HideDockPlugin(
            commandRunner: MockDockCommandRunner(),
            stateReader: { true }
        )

        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "已开启")
    }

    func testSwitchOnUpdatesDockState() {
        let runner = MockDockCommandRunner()
        let plugin = HideDockPlugin(
            commandRunner: runner,
            stateReader: { false }
        )

        plugin.handleAction(.setSwitch(true))

        XCTAssertEqual(runner.setDockAutohideCalls, [true])
        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertNil(plugin.primaryPanelState.errorMessage)
    }

    func testSwitchFailureKeepsPreviousStateAndSetsError() {
        let runner = MockDockCommandRunner()
        runner.shouldFailSet = true
        let plugin = HideDockPlugin(
            commandRunner: runner,
            stateReader: { false }
        )

        plugin.handleAction(.setSwitch(true))

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertNotNil(plugin.primaryPanelState.errorMessage)
    }

    func testDefaultPluginHostIncludesHideDock() {
        let host = PluginHost()

        XCTAssertTrue(host.featureManagementItems.contains { $0.id == "hide-dock" })
    }
}

private final class MockDockCommandRunner: DockCommandRunning {
    var shouldFailSet = false
    var setDockAutohideCalls: [Bool] = []

    func setDockAutohide(_ isEnabled: Bool) throws {
        if shouldFailSet {
            throw NSError(
                domain: "HideDockPluginTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "set failed"]
            )
        }

        setDockAutohideCalls.append(isEnabled)
    }
}

import XCTest
@testable import MacTools

@MainActor
final class HideDockPluginTests: XCTestCase {
    func testManifestIdentifiesHideDockPlugin() {
        let plugin = HideDockPlugin(
            commandRunner: MockDockCommandRunner(),
            stateReader: { false }
        )

        XCTAssertEqual(plugin.manifest.id, "hide-dock")
        XCTAssertEqual(plugin.manifest.title, "隐藏 Dock")
        XCTAssertEqual(plugin.manifest.controlStyle, .switch)
    }

    func testInitialStateReflectsStateReader() {
        let plugin = HideDockPlugin(
            commandRunner: MockDockCommandRunner(),
            stateReader: { true }
        )

        XCTAssertTrue(plugin.panelState.isOn)
        XCTAssertEqual(plugin.panelState.subtitle, "已开启")
    }

    func testSwitchOnUpdatesDockState() {
        let runner = MockDockCommandRunner()
        let plugin = HideDockPlugin(
            commandRunner: runner,
            stateReader: { false }
        )

        plugin.handlePanelAction(.setSwitch(true))

        XCTAssertEqual(runner.setDockAutohideCalls, [true])
        XCTAssertTrue(plugin.panelState.isOn)
        XCTAssertNil(plugin.panelState.errorMessage)
    }

    func testSwitchFailureKeepsPreviousStateAndSetsError() {
        let runner = MockDockCommandRunner()
        runner.shouldFailSet = true
        let plugin = HideDockPlugin(
            commandRunner: runner,
            stateReader: { false }
        )

        plugin.handlePanelAction(.setSwitch(true))

        XCTAssertFalse(plugin.panelState.isOn)
        XCTAssertNotNil(plugin.panelState.errorMessage)
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
import XCTest
@testable import AutoHideDockPlugin

@MainActor
final class AutoHideDockPluginTests: XCTestCase {
    func testMetadataIdentifiesAutoHideDockPlugin() {
        let plugin = AutoHideDockPlugin(
            commandRunner: MockDockCommandRunner(),
            stateReader: { false }
        )

        XCTAssertEqual(plugin.metadata.id, "auto-hide-dock")
        XCTAssertEqual(plugin.metadata.title, "自动隐藏程序坞")
        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .switch)
    }

    func testInitialStateReflectsStateReader() {
        let plugin = AutoHideDockPlugin(
            commandRunner: MockDockCommandRunner(),
            stateReader: { true }
        )

        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "已开启")
    }

    func testSwitchOnUpdatesDockState() {
        let runner = MockDockCommandRunner()
        let plugin = AutoHideDockPlugin(
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
        let plugin = AutoHideDockPlugin(
            commandRunner: runner,
            stateReader: { false }
        )

        plugin.handleAction(.setSwitch(true))

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertNotNil(plugin.primaryPanelState.errorMessage)
    }
}

private final class MockDockCommandRunner: DockCommandRunning {
    var shouldFailSet = false
    var setDockAutohideCalls: [Bool] = []

    func setDockAutohide(_ isEnabled: Bool) throws {
        if shouldFailSet {
            throw NSError(
                domain: "AutoHideDockPluginTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "set failed"]
            )
        }

        setDockAutohideCalls.append(isEnabled)
    }
}

import XCTest
@testable import StageManagerPlugin

@MainActor
final class StageManagerPluginTests: XCTestCase {
    func testMetadataIdentifiesStageManagerPlugin() {
        let plugin = StageManagerPlugin(
            commandRunner: MockStageManagerCommandRunner(),
            stateReader: { false }
        )

        XCTAssertEqual(plugin.metadata.id, "stage-manager")
        XCTAssertEqual(plugin.metadata.title, "台前调度")
        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .switch)
    }

    func testInitialStateReflectsStateReader() {
        let plugin = StageManagerPlugin(
            commandRunner: MockStageManagerCommandRunner(),
            stateReader: { true }
        )

        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertEqual(plugin.primaryPanelState.subtitle, "已开启")
    }

    func testSwitchOnUpdatesStageManagerState() {
        let runner = MockStageManagerCommandRunner()
        let plugin = StageManagerPlugin(
            commandRunner: runner,
            stateReader: { false }
        )

        plugin.handleAction(.setSwitch(true))

        XCTAssertEqual(runner.setStageManagerCalls, [true])
        XCTAssertTrue(plugin.primaryPanelState.isOn)
        XCTAssertNil(plugin.primaryPanelState.errorMessage)
    }

    func testSwitchFailureKeepsPreviousStateAndSetsError() {
        let runner = MockStageManagerCommandRunner()
        runner.shouldFailSet = true
        let plugin = StageManagerPlugin(
            commandRunner: runner,
            stateReader: { false }
        )

        plugin.handleAction(.setSwitch(true))

        XCTAssertFalse(plugin.primaryPanelState.isOn)
        XCTAssertNotNil(plugin.primaryPanelState.errorMessage)
    }
}

private final class MockStageManagerCommandRunner: StageManagerCommandRunning {
    var shouldFailSet = false
    var setStageManagerCalls: [Bool] = []

    func setStageManagerEnabled(_ isEnabled: Bool) throws {
        if shouldFailSet {
            throw NSError(
                domain: "StageManagerPluginTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "set failed"]
            )
        }

        setStageManagerCalls.append(isEnabled)
    }
}

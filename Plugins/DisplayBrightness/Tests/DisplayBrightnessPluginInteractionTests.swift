import XCTest
@testable import MacTools
@testable import DisplayBrightnessPlugin

@MainActor
final class DisplayBrightnessPluginInteractionTests: XCTestCase {
    func testExpandingPluginUsesExistingSnapshotWithoutRefreshingController() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))

        XCTAssertEqual(controller.refreshCount, 0)
        XCTAssertTrue(plugin.primaryPanelState.isExpanded)
    }

    func testSliderChangedForwardsDraftBrightnessValue() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(
            .setSlider(controlID: "display.2.brightness", value: 0.34, phase: .changed)
        )

        XCTAssertEqual(
            controller.setBrightnessCalls,
            [.init(value: 0.34, displayID: 2, phase: .changed)]
        )
    }

    func testSliderEndedForwardsFinalBrightnessValue() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(
            .setSlider(controlID: "display.2.brightness", value: 0.8, phase: .ended)
        )

        XCTAssertEqual(
            controller.setBrightnessCalls,
            [.init(value: 0.8, displayID: 2, phase: .ended)]
        )
    }

    func testInvalidSliderControlIDIsIgnored() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(
            .setSlider(controlID: "display.invalid", value: 0.8, phase: .ended)
        )

        XCTAssertTrue(controller.setBrightnessCalls.isEmpty)
    }

    func testShortcutPressAdjustsBrightnessByOnePercentInitially() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(
                    id: 2,
                    name: "Built-in Display",
                    brightness: 0.6,
                    vendorNumber: 1552,
                    modelNumber: 1,
                    serialNumber: 22
                )
            ],
            errorMessage: nil
        )
        let plugin = DisplayBrightnessPlugin(controller: controller)
        let displayKey = DisplayBrightnessPlugin.shortcutDisplayKey(
            for: controller.snapshotValue.displays[0].display
        )

        plugin.handleShortcutEvent(
            id: DisplayBrightnessPlugin.shortcutActionID(
                displayKey: displayKey,
                direction: .increase
            ),
            phase: .pressed
        )

        XCTAssertEqual(
            controller.setBrightnessCalls.first,
            .init(value: 0.61, displayID: 2, phase: .changed)
        )
    }

    func testRepeatedShortcutPressAcceleratesWhenTappedQuickly() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )
        let plugin = DisplayBrightnessPlugin(controller: controller)
        let displayKey = DisplayBrightnessPlugin.shortcutDisplayKey(
            for: controller.snapshotValue.displays[0].display
        )
        let actionID = DisplayBrightnessPlugin.shortcutActionID(
            displayKey: displayKey,
            direction: .increase
        )

        plugin.handleShortcutEvent(id: actionID, phase: .pressed)
        plugin.handleShortcutEvent(id: actionID, phase: .released)
        plugin.handleShortcutEvent(id: actionID, phase: .pressed)
        plugin.handleShortcutEvent(id: actionID, phase: .released)

        XCTAssertEqual(controller.setBrightnessCalls[0].value, 0.61, accuracy: 0.0001)
        XCTAssertEqual(controller.setBrightnessCalls[2].value, 0.63, accuracy: 0.0001)
    }

    func testShortcutReleaseCommitsCurrentBrightness() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Built-in Display", brightness: 0.6)
            ],
            errorMessage: nil
        )
        let plugin = DisplayBrightnessPlugin(controller: controller)
        let displayKey = DisplayBrightnessPlugin.shortcutDisplayKey(
            for: controller.snapshotValue.displays[0].display
        )
        let actionID = DisplayBrightnessPlugin.shortcutActionID(
            displayKey: displayKey,
            direction: .decrease
        )

        plugin.handleShortcutEvent(id: actionID, phase: .pressed)
        plugin.handleShortcutEvent(id: actionID, phase: .released)

        XCTAssertEqual(
            controller.setBrightnessCalls.last,
            .init(value: 0.59, displayID: 2, phase: .ended)
        )
    }
}

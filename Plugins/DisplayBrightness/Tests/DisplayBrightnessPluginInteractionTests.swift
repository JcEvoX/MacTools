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

    func testExpandedDetailShowsBuiltInDisplayDisableActionWhenAllowed() {
        let brightness = MockDisplayBrightnessController()
        brightness.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "Studio Display", brightness: 0.7)
            ],
            errorMessage: nil
        )
        let displayDisable = MockDisplayDisableCoordinator()
        displayDisable.snapshotValue = DisplayDisableSnapshot(
            status: .available,
            isDisableAllowed: true,
            isRestoreAllowed: false,
            externalDisplayCount: 1,
            message: nil
        )
        let plugin = DisplayBrightnessPlugin(
            controller: brightness,
            displayDisableCoordinator: displayDisable,
            showsDisplayDisableControls: true
        )

        plugin.handleAction(.setDisclosureExpanded(true))

        let controls = plugin.primaryPanelState.detail?.primaryControls ?? []
        let action = controls.first { $0.id == "built-in-display-disable" }
        XCTAssertEqual(action?.kind, .actionRow)
        XCTAssertEqual(action?.actionTitle, "关闭内建显示屏")
        XCTAssertEqual(action?.actionIconSystemName, "display")
        XCTAssertTrue(action?.isEnabled == true)
    }

    func testExpandedDetailShowsDisabledBuiltInDisplayDisableActionWhenUnsupported() {
        let brightness = MockDisplayBrightnessController()
        brightness.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "内建视网膜显示器", brightness: 0.7),
                makeBrightnessDisplay(id: 3, name: "Studio Display", brightness: 0.38)
            ],
            errorMessage: nil
        )
        let displayDisable = MockDisplayDisableCoordinator()
        displayDisable.snapshotValue = .unsupported
        let plugin = DisplayBrightnessPlugin(
            controller: brightness,
            displayDisableCoordinator: displayDisable,
            showsDisplayDisableControls: true
        )

        plugin.handleAction(.setDisclosureExpanded(true))

        let controls = plugin.primaryPanelState.detail?.primaryControls ?? []
        let action = controls.first { $0.id == "built-in-display-disable" }
        XCTAssertEqual(action?.kind, .actionRow)
        XCTAssertEqual(action?.actionTitle, "关闭内建显示屏")
        XCTAssertEqual(action?.actionIconSystemName, "display")
        XCTAssertTrue(action?.isEnabled == false)
    }

    func testBuiltInDisplayDisableActionIsVisibleByDefault() {
        let brightness = MockDisplayBrightnessController()
        brightness.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 2, name: "内建视网膜显示器", brightness: 0.7),
                makeBrightnessDisplay(id: 3, name: "Studio Display", brightness: 0.38)
            ],
            errorMessage: nil
        )
        let displayDisable = MockDisplayDisableCoordinator()
        displayDisable.snapshotValue = .unsupported
        let plugin = DisplayBrightnessPlugin(
            controller: brightness,
            displayDisableCoordinator: displayDisable
        )

        plugin.handleAction(.setDisclosureExpanded(true))

        let controls = plugin.primaryPanelState.detail?.primaryControls ?? []
        let action = controls.first { $0.id == "built-in-display-disable" }
        XCTAssertEqual(action?.kind, .actionRow)
        XCTAssertEqual(action?.actionTitle, "关闭内建显示屏")
        XCTAssertTrue(action?.isEnabled == false)
    }

    func testDisableActionForwardsToCoordinator() async {
        let displayDisable = MockDisplayDisableCoordinator()
        let plugin = DisplayBrightnessPlugin(
            controller: MockDisplayBrightnessController(),
            displayDisableCoordinator: displayDisable
        )

        plugin.handleAction(.invokeAction(controlID: "built-in-display-disable"))

        await waitUntil {
            displayDisable.disableCallCount == 1
        }
    }

    func testRestoreActionForwardsToCoordinatorSynchronously() {
        let displayDisable = MockDisplayDisableCoordinator()
        let plugin = DisplayBrightnessPlugin(
            controller: MockDisplayBrightnessController(),
            displayDisableCoordinator: displayDisable
        )

        plugin.handleAction(.invokeAction(controlID: "built-in-display-restore"))

        XCTAssertEqual(displayDisable.restoreCallCount, 1)
    }

    func testRefreshRefreshesDisplayDisableSnapshot() {
        let displayDisable = MockDisplayDisableCoordinator()
        let plugin = DisplayBrightnessPlugin(
            controller: MockDisplayBrightnessController(),
            displayDisableCoordinator: displayDisable
        )

        plugin.refresh()

        XCTAssertEqual(displayDisable.refreshSnapshotCallCount, 1)
    }

    func testRefreshDisplayTopologyReconcilesDisplayDisableState() async {
        let displayDisable = MockDisplayDisableCoordinator()
        let plugin = DisplayBrightnessPlugin(
            controller: MockDisplayBrightnessController(),
            displayDisableCoordinator: displayDisable
        )

        plugin.refreshDisplayTopology()

        await waitUntil {
            displayDisable.reconcileCallCount == 1
        }
    }

    func testDeactivateRestoresBuiltInDisplayForCleanupReason() {
        let displayDisable = MockDisplayDisableCoordinator()
        let plugin = DisplayBrightnessPlugin(
            controller: MockDisplayBrightnessController(),
            displayDisableCoordinator: displayDisable
        )

        plugin.deactivate(reason: .hostShutdown)

        XCTAssertEqual(displayDisable.restoreCallCount, 1)
    }

    func testDeactivateDoesNotRestoreBuiltInDisplayDuringUpdate() {
        let displayDisable = MockDisplayDisableCoordinator()
        let plugin = DisplayBrightnessPlugin(
            controller: MockDisplayBrightnessController(),
            displayDisableCoordinator: displayDisable
        )

        plugin.deactivate(reason: .updating)

        XCTAssertEqual(displayDisable.restoreCallCount, 0)
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

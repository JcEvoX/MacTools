import XCTest
@testable import MacTools
@testable import DisplayBrightnessPlugin

@MainActor
final class DisplayBrightnessPluginTests: XCTestCase {
    func testParseDisplayIDExtractsNumericIdentifier() {
        XCTAssertEqual(
            DisplayBrightnessPlugin.parseDisplayID(from: "display.42.brightness"),
            42
        )
    }

    func testParseDisplayIDRejectsUnexpectedControlID() {
        XCTAssertNil(DisplayBrightnessPlugin.parseDisplayID(from: "display.42"))
        XCTAssertNil(DisplayBrightnessPlugin.parseDisplayID(from: "brightness.42"))
        XCTAssertNil(DisplayBrightnessPlugin.parseDisplayID(from: "display.foo.brightness"))
    }

    func testEmptySnapshotDisablesPluginAndSuppressesDetail() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(displays: [], errorMessage: nil)

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))

        let state = plugin.primaryPanelState

        XCTAssertEqual(state.subtitle, "未检测到可调节亮度的显示器")
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.isExpanded)
        XCTAssertNil(state.detail)
    }

    func testSingleDisplaySummaryIncludesDisplayNameAndBrightness() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)

        XCTAssertEqual(plugin.primaryPanelState.subtitle, "Studio Display 72%")
    }

    func testMultipleDisplaysSummaryUsesDisplayCount() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72),
                makeBrightnessDisplay(id: 9, name: "LG UltraFine", brightness: 0.41)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)

        XCTAssertEqual(plugin.primaryPanelState.subtitle, "2 个显示器")
    }

    func testExpandedStateBuildsOneSliderPerDisplay() throws {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72),
                makeBrightnessDisplay(id: 9, name: "LG UltraFine", brightness: 0.41)
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))

        let controls = try XCTUnwrap(plugin.primaryPanelState.detail?.primaryControls)

        XCTAssertEqual(controls.count, 2)
        XCTAssertEqual(controls.map(\.kind), [.slider, .slider])
        XCTAssertEqual(controls.map(\.id), ["display.7.brightness", "display.9.brightness"])
        XCTAssertEqual(controls.map(\.sectionTitle), ["Studio Display", "LG UltraFine"])
        XCTAssertEqual(controls.map(\.valueLabel), ["72%", "41%"])
        XCTAssertEqual(controls.first?.sliderBounds, 0...1)
        XCTAssertEqual(controls.first?.sliderStep, 0.01)
    }

    func testShortcutDefinitionsIncludeDecreaseAndIncreaseForEachDisplay() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(
                    id: 7,
                    name: "Studio Display",
                    brightness: 0.72,
                    vendorNumber: 0x610,
                    modelNumber: 32,
                    serialNumber: 9001
                )
            ],
            errorMessage: nil
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)
        let definitions = plugin.shortcutDefinitions

        XCTAssertEqual(definitions.count, 2)
        XCTAssertEqual(definitions.map(\.settingsGroupTitle), ["Studio Display", "Studio Display"])
        XCTAssertEqual(
            definitions.map(\.settingsGroupDescription),
            [
                "可与其他显示器使用相同快捷键，同时调节。",
                "可与其他显示器使用相同快捷键，同时调节。"
            ]
        )
        XCTAssertEqual(definitions.map(\.settingsControlTitle), ["降低", "增加"])
        XCTAssertEqual(definitions.map(\.settingsControlSystemImage), ["sun.min.fill", "sun.max.fill"])
        XCTAssertEqual(
            definitions.map(\.sharedBindingGroupID),
            ["display-brightness.decrease", "display-brightness.increase"]
        )
        XCTAssertEqual(definitions.map(\.scope), [.global, .global])
    }

    func testShortcutDisplayKeyPrefersStableSerialIdentity() {
        let display = makeTestDisplay(
            id: 7,
            name: "Studio Display",
            vendorNumber: 0x610,
            modelNumber: 32,
            serialNumber: 9001
        )

        XCTAssertEqual(
            DisplayBrightnessPlugin.shortcutDisplayKey(for: display),
            "v1552-m32-s9001"
        )
    }

    func testParseShortcutActionIDExtractsDisplayKeyAndDirection() throws {
        let action = try XCTUnwrap(
            DisplayBrightnessPlugin.parseShortcutActionID(
                "display-brightness.display.v1552-m32-s9001.increase"
            )
        )

        XCTAssertEqual(action.displayKey, "v1552-m32-s9001")
        XCTAssertEqual(action.direction, .increase)
    }

    func testErrorMessageIsExposedFromSnapshot() {
        let controller = MockDisplayBrightnessController()
        controller.snapshotValue = DisplayBrightnessSnapshot(
            displays: [
                makeBrightnessDisplay(id: 7, name: "Studio Display", brightness: 0.72)
            ],
            errorMessage: "调节失败：DDC 写入失败"
        )

        let plugin = DisplayBrightnessPlugin(controller: controller)

        XCTAssertEqual(plugin.primaryPanelState.errorMessage, "调节失败：DDC 写入失败")
    }
}

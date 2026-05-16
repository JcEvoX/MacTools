import CoreGraphics
import XCTest
@testable import MacTools

@MainActor
final class DisplayResolutionPluginSidePanelTests: XCTestCase {
    func testNavigationOmitsDisplaysWithoutVisibleModes() throws {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true),
            makeDisplay(id: 4, name: "Projector")
        ]
        controller.modesByDisplayID = [
            2: [makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true)],
            4: []
        ]

        let plugin = DisplayResolutionPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))

        let navigation = try XCTUnwrap(plugin.primaryPanelState.detail?.primaryControls.first)
        XCTAssertEqual(navigation.options.map(\.id), ["2"])
    }

    func testExpandedStateShowsDisplayNavigationAndNoSecondaryPanelByDefault() throws {
        let plugin = makePlugin()
        plugin.handleAction(.setDisclosureExpanded(true))

        let detail = try XCTUnwrap(plugin.primaryPanelState.detail)

        XCTAssertEqual(detail.primaryControls.count, 2)
        XCTAssertEqual(detail.primaryControls[0].kind, .navigationList)
        XCTAssertEqual(detail.primaryControls[1].kind, .actionRow)
        XCTAssertNil(detail.primaryControls[0].selectedOptionID)
        XCTAssertNil(detail.secondaryPanel)
    }

    func testExpandedStateCanResolveHoveredDisplayPanelWithoutSelectingDisplay() throws {
        let plugin = makePlugin()
        plugin.handleAction(.setDisclosureExpanded(true))

        let detail = try XCTUnwrap(plugin.primaryPanelState.detail)
        let studioPanel = try XCTUnwrap(
            detail.secondaryPanel(controlID: "display-navigation", optionID: "2")
        )
        let lgPanel = try XCTUnwrap(
            detail.secondaryPanel(controlID: "display-navigation", optionID: "3")
        )

        XCTAssertNil(detail.primaryControls[0].selectedOptionID)
        XCTAssertNil(detail.secondaryPanel)
        XCTAssertEqual(studioPanel.title, "Studio Display")
        XCTAssertEqual(studioPanel.controls.first?.id, "display.2")
        XCTAssertEqual(lgPanel.title, "LG UltraFine")
        XCTAssertEqual(lgPanel.controls.first?.id, "display.3")
        XCTAssertNil(detail.secondaryPanel(controlID: "display-navigation", optionID: "missing"))
    }

    func testSelectingDisplayShowsSecondaryPanel() throws {
        let plugin = makePlugin()
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))

        let secondary = try XCTUnwrap(plugin.primaryPanelState.detail?.secondaryPanel)
        XCTAssertEqual(secondary.title, "Studio Display")
        XCTAssertEqual(secondary.controls.first?.kind, .selectList)
    }

    func testClearingNavigationSelectionClosesSecondaryPanel() {
        let plugin = makePlugin()
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))
        plugin.handleAction(.clearNavigationSelection(controlID: "display-navigation"))

        XCTAssertNil(plugin.primaryPanelState.detail?.secondaryPanel)
    }

    func testSelectingResolutionInSecondaryPanelAppliesModeOnSelectedDisplay() throws {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true),
            makeDisplay(id: 3, name: "LG UltraFine")
        ]
        controller.modesByDisplayID = [
            2: [
                makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true),
                makeMode(modeId: 12, width: 2560, height: 1440)
            ],
            3: [
                makeMode(modeId: 12, width: 3008, height: 1692, isCurrent: true)
            ]
        ]

        let plugin = DisplayResolutionPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))

        let controlID = try XCTUnwrap(plugin.primaryPanelState.detail?.secondaryPanel?.controls.first?.id)
        plugin.handleAction(.setSelection(controlID: controlID, optionID: "12"))

        XCTAssertEqual(controller.applyCalls.count, 1)
        XCTAssertEqual(controller.applyCalls[0].displayID, 2)
        XCTAssertEqual(controller.applyCalls[0].modeId, 12)
    }

    func testCollapsingPluginClearsSelectedDisplay() {
        let plugin = makePlugin()
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))
        plugin.handleAction(.setDisclosureExpanded(false))

        XCTAssertNil(plugin.primaryPanelState.detail)
        plugin.handleAction(.setDisclosureExpanded(true))
        XCTAssertNil(plugin.primaryPanelState.detail?.secondaryPanel)
    }

    func testMissingSelectedDisplayClearsSecondaryPanel() {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true),
            makeDisplay(id: 3, name: "LG UltraFine")
        ]
        controller.modesByDisplayID = [
            2: [makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true)],
            3: [makeMode(modeId: 30, width: 3008, height: 1692, isCurrent: true)]
        ]

        let plugin = DisplayResolutionPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))

        controller.displays = [
            makeDisplay(id: 3, name: "LG UltraFine")
        ]
        plugin.refresh()

        XCTAssertNil(plugin.primaryPanelState.detail?.secondaryPanel)
        XCTAssertNil(plugin.primaryPanelState.detail?.primaryControls.first?.selectedOptionID)
        XCTAssertEqual(plugin.primaryPanelState.detail?.primaryControls.first?.options.map(\.id), ["3"])
    }

    func testAllFilteredDisplaysDisablePluginAndSuppressDetail() {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true)
        ]
        controller.modesByDisplayID = [2: []]

        let plugin = DisplayResolutionPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))

        let state = plugin.primaryPanelState

        XCTAssertEqual(state.subtitle, "未检测到可用分辨率")
        XCTAssertFalse(state.isEnabled)
        XCTAssertFalse(state.isExpanded)
        XCTAssertNil(state.detail)
    }

    func testExpandedDetailExposesOpenSystemSettingsActionRow() throws {
        let plugin = makePlugin()
        plugin.handleAction(.setDisclosureExpanded(true))

        let controls = try XCTUnwrap(plugin.primaryPanelState.detail?.primaryControls)
        let actionRow = try XCTUnwrap(controls.last)

        XCTAssertEqual(actionRow.kind, .actionRow)
        XCTAssertEqual(actionRow.id, "display-open-system-settings")
        XCTAssertEqual(actionRow.actionTitle, "打开系统显示器设置")
        XCTAssertEqual(actionRow.actionIconSystemName, "gearshape")
        XCTAssertEqual(actionRow.actionBehavior, .dismissBeforeHandling)
        XCTAssertTrue(actionRow.showsLeadingDivider)
    }

    func testInvokeOpenSystemSettingsActionAsksLauncherToOpen() {
        let launcher = MockSystemSettingsLauncher()
        let controller = MockDisplayResolutionController()
        controller.displays = [makeDisplay(id: 2, name: "Studio Display", isMain: true)]
        controller.modesByDisplayID = [
            2: [makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true)]
        ]

        let plugin = DisplayResolutionPlugin(
            controller: controller,
            systemSettingsLauncher: launcher
        )
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(.invokeAction(controlID: "display-open-system-settings"))

        XCTAssertEqual(launcher.openCallCount, 1)
    }

    func testInvokeUnknownActionDoesNotInvokeLauncher() {
        let launcher = MockSystemSettingsLauncher()
        let plugin = DisplayResolutionPlugin(
            controller: MockDisplayResolutionController(),
            systemSettingsLauncher: launcher
        )

        plugin.handleAction(.invokeAction(controlID: "something-else"))

        XCTAssertEqual(launcher.openCallCount, 0)
    }

    func testCollapsedPluginDoesNotExposeActionRow() {
        let plugin = makePlugin()

        XCTAssertNil(plugin.primaryPanelState.detail)
    }

    func testSelectingDifferentDisplayClearsLastErrorMessage() throws {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true),
            makeDisplay(id: 3, name: "LG UltraFine")
        ]
        controller.modesByDisplayID = [
            2: [
                makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true),
                makeMode(modeId: 12, width: 2560, height: 1440)
            ],
            3: [
                makeMode(modeId: 30, width: 3008, height: 1692, isCurrent: true)
            ]
        ]
        controller.applyResult = .failure(.modeNotFound(modeId: 12))

        let plugin = DisplayResolutionPlugin(controller: controller)
        plugin.handleAction(.setDisclosureExpanded(true))
        plugin.handleAction(.setNavigationSelection(controlID: "display-navigation", optionID: "2"))

        let controlID = try XCTUnwrap(plugin.primaryPanelState.detail?.secondaryPanel?.controls.first?.id)
        plugin.handleAction(.setSelection(controlID: controlID, optionID: "12"))
        XCTAssertNotNil(plugin.primaryPanelState.errorMessage)

        plugin.handleAction(.setNavigationSelection(controlID: "display-navigation", optionID: "3"))
        XCTAssertNil(plugin.primaryPanelState.errorMessage)
    }

    func testPanelStateUsesCachedResolutionSnapshot() {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true)
        ]
        controller.modesByDisplayID = [
            2: [makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true)]
        ]

        let plugin = DisplayResolutionPlugin(controller: controller)
        controller.listConnectedDisplaysCount = 0
        controller.listAvailableResolutionsCount = 0

        _ = plugin.primaryPanelState
        plugin.handleAction(.setDisclosureExpanded(true))
        _ = plugin.primaryPanelState
        _ = plugin.primaryPanelState.detail?.secondaryPanel(controlID: "display-navigation", optionID: "2")

        XCTAssertEqual(controller.listConnectedDisplaysCount, 0)
        XCTAssertEqual(controller.listAvailableResolutionsCount, 0)
    }

    func testRefreshUpdatesResolutionSnapshot() {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true)
        ]
        controller.modesByDisplayID = [
            2: [makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true)]
        ]

        let plugin = DisplayResolutionPlugin(controller: controller)
        controller.modesByDisplayID = [
            2: [makeMode(modeId: 12, width: 2560, height: 1440, isCurrent: true)]
        ]

        plugin.refresh()

        XCTAssertEqual(plugin.primaryPanelState.subtitle, "主屏 2560×1440")
    }

    private func makePlugin() -> DisplayResolutionPlugin {
        let controller = MockDisplayResolutionController()
        controller.displays = [
            makeDisplay(id: 2, name: "Studio Display", isMain: true),
            makeDisplay(id: 3, name: "LG UltraFine")
        ]
        controller.modesByDisplayID = [
            2: [
                makeMode(modeId: 8, width: 1920, height: 1080, isCurrent: true),
                makeMode(modeId: 12, width: 2560, height: 1440)
            ],
            3: [
                makeMode(modeId: 30, width: 3008, height: 1692, isCurrent: true)
            ]
        ]
        return DisplayResolutionPlugin(controller: controller)
    }

    private func makeMode(
        modeId: Int32,
        width: Int,
        height: Int,
        isCurrent: Bool = false
    ) -> DisplayResolutionInfo {
        DisplayResolutionInfo(
            modeId: modeId,
            width: width,
            height: height,
            pixelWidth: width * 2,
            pixelHeight: height * 2,
            refreshRate: 60,
            isHiDPI: true,
            isNative: false,
            isDefault: false,
            isCurrent: isCurrent
        )
    }

    private func makeDisplay(
        id: CGDirectDisplayID,
        name: String,
        isMain: Bool = false
    ) -> DisplayInfo {
        DisplayInfo(
            id: id,
            name: name,
            isBuiltin: false,
            isMain: isMain,
            vendorNumber: nil,
            modelNumber: nil,
            serialNumber: nil
        )
    }
}

@MainActor
private final class MockSystemSettingsLauncher: DisplaySystemSettingsLauncher {
    private(set) var openCallCount = 0

    @discardableResult
    func openDisplaySettings() -> Bool {
        openCallCount += 1
        return true
    }
}

@MainActor
private final class MockDisplayResolutionController: DisplayResolutionControlling {
    struct ApplyCall: Equatable {
        let displayID: CGDirectDisplayID
        let modeId: Int32
    }

    var displays: [DisplayInfo] = []
    var modesByDisplayID: [CGDirectDisplayID: [DisplayResolutionInfo]] = [:]
    var applyCalls: [ApplyCall] = []
    var applyResult: Result<Void, DisplayResolutionError> = .success(())
    var listConnectedDisplaysCount = 0
    var listAvailableResolutionsCount = 0

    func listConnectedDisplays() -> [DisplayInfo] {
        listConnectedDisplaysCount += 1
        return displays
    }

    func listAvailableResolutions(for displayID: CGDirectDisplayID) -> [DisplayResolutionInfo] {
        listAvailableResolutionsCount += 1
        return modesByDisplayID[displayID] ?? []
    }

    func applyResolution(
        _ info: DisplayResolutionInfo,
        for displayID: CGDirectDisplayID
    ) -> Result<Void, DisplayResolutionError> {
        applyCalls.append(ApplyCall(displayID: displayID, modeId: info.modeId))
        return applyResult
    }
}

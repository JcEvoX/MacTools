import AppKit
import SwiftUI
import XCTest
import MacToolsPluginKit
@testable import MacTools

final class MenuBarPanelLayoutTests: XCTestCase {
    func testBaseLayoutMetricsStayStable() {
        XCTAssertEqual(MenuBarPanelLayout.baseWidth, 288)
        XCTAssertEqual(
            MenuBarPanelLayout.surfaceWidth,
            MenuBarPanelLayout.baseWidth - (MenuBarPanelLayout.outerPadding * 2)
        )
    }

    func testContentSizeUsesModelWithoutSwiftUILayoutMeasurement() {
        let item = makeItem(
            controlStyle: .disclosure,
            isExpanded: true,
            controls: [
                PluginPanelControl(
                    id: "display-navigation",
                    kind: .navigationList,
                    options: [
                        PluginPanelControlOption(id: "1", title: "Studio Display"),
                        PluginPanelControlOption(id: "2", title: "LG UltraFine")
                    ],
                    selectedOptionID: nil,
                    dateValue: nil,
                    minimumDate: nil,
                    displayedComponents: nil,
                    datePickerStyle: nil,
                    sectionTitle: nil,
                    isEnabled: true
                )
            ]
        )

        XCTAssertEqual(
            MenuBarPanelLayout.contentSize(for: [item]),
            NSSize(width: 288, height: 251)
        )
    }

    func testPreferredPanelHeightCapsTallFeatureLists() {
        let items = (0..<40).map { index in
            makeItem(id: "plugin-\(index)", controlStyle: .switch, isExpanded: false)
        }

        XCTAssertEqual(
            MenuBarPanelLayout.preferredPanelHeight(for: items, screen: nil),
            MenuBarPanelLayout.featureListMaximumHeight + MenuBarPanelLayout.fixedFooterHeight
        )
        XCTAssertEqual(MenuBarPanelLayout.maximumPanelHeight(visibleFrameHeight: 1000), 750)
    }

    func testEmptyContentSizeIncludesMarketplacePrompt() {
        XCTAssertEqual(
            MenuBarPanelLayout.contentSize(for: []),
            NSSize(width: 288, height: 247)
        )
    }

    private func makeItem(
        id: String = "display-resolution",
        controlStyle: PluginControlStyle,
        isExpanded: Bool,
        controls: [PluginPanelControl] = []
    ) -> PluginPanelItem {
        PluginPanelItem(
            id: id,
            title: "显示器分辨率",
            iconName: "display",
            iconTint: Color(nsColor: .systemBlue),
            controlStyle: controlStyle,
            menuActionBehavior: .keepPresented,
            description: "查看并切换每个显示器的分辨率",
            helpText: "查看并切换每个显示器的分辨率",
            descriptionTone: .secondary,
            isOn: false,
            isExpanded: isExpanded,
            isEnabled: true,
            detail: PluginPanelDetail(primaryControls: controls, secondaryPanel: nil),
            buttonActionID: nil,
            buttonTitle: nil
        )
    }
}

@MainActor
final class HoverSecondaryPanelCoordinatorTests: XCTestCase {
    func testSwitchingActivationClearsPreviousAnchor() {
        let coordinator = HoverSecondaryPanelCoordinator(
            dismissDelay: .milliseconds(5),
            activationDelay: nil
        )
        let firstActivation = makeActivation(optionID: "2")
        let secondActivation = makeActivation(optionID: "3")

        coordinator.hoverBegan(
            pluginID: firstActivation.pluginID,
            controlID: firstActivation.controlID,
            optionID: firstActivation.optionID
        )
        coordinator.updateRowFrame(
            CGRect(x: 10, y: 20, width: 30, height: 40),
            for: firstActivation
        )
        coordinator.hoverBegan(
            pluginID: secondActivation.pluginID,
            controlID: secondActivation.controlID,
            optionID: secondActivation.optionID
        )

        XCTAssertEqual(coordinator.activeActivation, secondActivation)
        XCTAssertNil(coordinator.selectedRowFrame)
    }

    func testHoverBeganUsesCachedFrameForNewActivation() {
        let coordinator = HoverSecondaryPanelCoordinator(
            dismissDelay: .milliseconds(5),
            activationDelay: nil
        )
        let activation = makeActivation(optionID: "3")
        let frame = CGRect(x: 30, y: 40, width: 120, height: 48)

        coordinator.updateRowFrame(frame, for: activation)
        coordinator.hoverBegan(
            pluginID: activation.pluginID,
            controlID: activation.controlID,
            optionID: activation.optionID
        )

        XCTAssertEqual(coordinator.activeActivation, activation)
        XCTAssertEqual(coordinator.selectedRowFrame, frame)
    }

    private func makeActivation(optionID: String) -> HoverSecondaryPanelCoordinator.Activation {
        HoverSecondaryPanelCoordinator.Activation(
            pluginID: "display-resolution",
            controlID: "display-navigation",
            optionID: optionID
        )
    }
}
